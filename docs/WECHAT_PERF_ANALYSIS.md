# 微信端"缆车卡帧移动"深度分析与重做方案

> 分析对象：CableCarAdventure（skywire-remake），Godot 4.5 + `gl_compatibility` + 微信小游戏
> 硬约束：**帧率上限 60 与 DPR 1.5 不得下调**；不得牺牲画面清晰度、操作手感、碰撞判定精度
> 本文所有结论均带 `文件名:行号` 证据，只读分析，未修改任何代码

---

## 结论速览

"卡帧移动"**不是帧率不够，而是帧率不稳时物理步与渲染步错位**。
微信端渲染帧间隔抖动时，Godot 会在一个渲染帧内补跑 0 次或 2 次 `_physics_process`，
缆车位置随之"走两步、停一步"——这正是用户看到的顿挫。

按投入产出排序，四条主线：

| 优先级 | 措施 | 解决的问题 | 风险 |
|---|---|---|---|
| **P0** | 开启物理插值 + 精准豁免 | 卡帧移动（直接根因） | 中：需逐个豁免 `_process` 改位置的节点 |
| **P1** | 轨道分块裁剪 + 背景烘焙 | 每帧 ~1000 个无效绘制指令 | 中：需重构两个渲染器 |
| **P2** | 缆车停止无条件重绘 | 每秒 120 次顶点重建 | 低 |
| **P3** | 轨道几何算法与内存 | 飞跃断口时的尖刺卡顿 | 低 |

---

## 一、根因 A：物理帧与渲染帧错位（卡帧移动的直接原因）

### 证据链

1. 缆车位置在**物理帧**更新：`coaster_controller.gd:510` `_physics_process` → `:585` `_update_pose()` → `:898` `global_position = track.sample_at(current_s)`
2. 相机在**渲染帧**更新：`game_controller.gd:167` `_process` → `:287` `camera.global_position = _get_camera_target()`
3. **`project.godot` 中完全没有 `[physics]` 段**（已 Grep 确认）→ 全部走引擎默认值：
   - `physics_ticks_per_second = 60`
   - **`physics_interpolation = false`（默认关闭）** ← 关键
   - `max_physics_steps_per_frame = 8`
4. 微信档 `PlatformConfig`：`max_fps = 60`

### 机制

微信 WebView 的真机 rAF 帧间隔**极不稳定**（后台节流、WASM GC、WebGL 提交阻塞都会让单帧耗时冲到 25~40ms）。
当渲染帧间隔 > 16.67ms：

- 该帧内 Godot 补跑 **2 次** `_physics_process` → 缆车一帧前进 `2 × 720/60 = 24px`
- 下一帧可能只跑 **0 次** → 缆车**完全静止**

于是视觉上是"窜一下、停一下"的顿挫。**这与平均帧率数值无关**——即使平均 45fps 也照样抖，
因为问题出在**步长不均匀**，而不是步数太少。

桌面端 rAF 稳定 60Hz，1 渲染帧恒等于 1 物理帧，永远对齐，所以本地测试看不出来。

### 放大因素

相机（`_process`）与缆车（`_physics_process`）在不同回调更新。同一渲染帧内，相机可能读到
"缆车还没动"或"缆车已经动了两次"的位置，两者错位进一步放大画面抖动。

---

## 二、关键有利条件：缆车其实是纯运动学，不依赖 Godot 物理

这一条决定了 P0 方案可以做得多干净。

### 证据

- 全项目 Grep `move_and_slide` → **零命中**。缆车虽 `extends CharacterBody2D`（`coaster_controller.gd:2`），却从不调用物理引擎的移动函数，只是沿弧长 `current_s` 手动积分（`:563` `current_s += current_speed * delta`）
- 全部 9 个缆车场景都是 `collision_layer = 2` + **`collision_mask = 0`**（`dove.tscn:13-14`，其余 8 个同构）→ 缆车**不主动检测任何东西**
- 缆车场景极轻：2 个 `Sprite2D`（`BGSprite` + `BodySprite`）+ 1 个 `CollisionShape2D` + `PassengerSeats`（`dove.tscn:21-36`）
- 交互全部由**对方的 `Area2D`** 发起：障碍 `collision_mask = 2`（`barrier.tscn:37-39`，`monitorable = false`），终点门 `collision_layer = 16 / collision_mask = 2`（`finish_gate.tscn:66-68`）
- `obstacle.gd:176` `body_entered.connect(...)`、`finish_gate.gd:33` 同理

**含义：** 缆车在物理帧里唯一必须完成的事，是**在 Area2D 做重叠检测之前把 `global_position` 写好**。
它对物理引擎没有任何反向依赖。

### 两条修复路线对比

**路线 1（推荐）：开启全局物理插值**

```
[physics]
common/physics_interpolation=true
```

缆车留在 `_physics_process`，渲染时引擎自动对前后两个物理快照插值。
**碰撞检测时序完全不变**，判定精度零损失——满足用户的硬约束。

**路线 2（备选）：把缆车移到 `_process`**

位置更新与渲染天然同帧，从根上消除对齐问题，还能省掉一次物理/渲染边界。
**但代价是碰撞精度**：Area2D 的重叠检测在物理帧内基于位置快照进行，缆车改在 `_process`
更新后，Area2D 最多滞后 1 个物理帧才看到新位置。在 `max_speed = 720`（`coaster_controller.gd:33`）下
即 **12px 的位置误差**，会表现为"看着撞上了却没判定"或"提前掉血"。
用户明确要求不得牺牲碰撞判定精度，**故不推荐**。

### 路线 1 的雷区（必须逐个处理）

Godot 4 的 `physics_interpolation` 是**全局开关**，会影响所有 `Node2D`。
凡是**在 `_process` 里直接改 `global_position`** 的节点，开启后会**额外滞后一帧**
（因为插值采样的是物理帧快照，而 `_process` 的改动要等下一个物理 tick 才被采到）。

需要显式设置 `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` 的节点：

| 文件:行 | 节点 | 为什么要豁免 |
|---|---|---|
| `game_controller.gd:287` | 相机 | 在 `_process` 里 lerp，插值会让相机比缆车慢一帧，反而加重抖动感 |
| `duo_game_controller.gd:206` | 双人相机 | 同上 |
| `obstacle.gd:1038` | 移动障碍 | `_position_at_progress` 在 `_process` 里算，插值会导致视觉滞后于 Area2D 判定 |
| `obstacle.gd:259,715,745,764,779,794,803,1002,1018,1027` | 障碍复位/传送 | 瞬移类位置写入，插值会画出"飞过去的残影" |
| `passenger_eject.gd:24` | 弹出乘客 | 瞬移 |
| `meteor_trail.gd` / `ferris_wheel_visual.gd` | 特效 | 纯视觉，无需插值 |

**保持插值 ON 的只有缆车本体。**

另外，缆车自身的三处瞬移必须调 `reset_physics_interpolation()`，否则会插值出一段"滑行"：
- `coaster_controller.gd:491`（双人模式同步位置）
- `coaster_controller.gd:614`（`_begin_flight` 起飞，把缆车吸附到出口点）
- `coaster_controller.gd:898`（`_update_pose`，此处是正常行驶，**不要**加）
  → 准确说：`:898` 是每帧正常写入，属插值的正常输入；需要 reset 的是 `:491` 和 `:614`，
  以及 `:411` 传送闪光、瞬移相关路径（`_perform_blink`）

**验证方法：** 开启后录屏逐帧对比"缆车每帧位移像素"的方差。方差应从当前的剧烈波动降到接近 0。

---

## 三、根因 B：轨道层每帧提交上千个绘制指令，90% 在屏幕外

### 证据

- `track_renderer.gd:122` `_draw()` 一次性绘制**整条轨道的全部 piece**
- 贴图分支 `_draw_piece_texture` → `_get_piece_quads` 按 `step = 18.0` 切四边形
  → 12000px 轨道 ≈ **667 个 `draw_polygon`**（带贴图 + UV + 顶点色）
- 无贴图兜底分支：每 piece 5 条 `draw_polyline` + 枕木每 26px 一条 `draw_line`（≈460 条）+ 方向箭头每 320px 一个 `draw_colored_polygon`
- **没有任何基于相机可见范围的裁剪**

### 需要准确区分的一点

`track_renderer.gd:61` 有 `set_process(false)`，静态轨道**不会每帧重跑 GDScript 的 `_draw()`**——
这个设计是对的（`_piece_quads_cache` 也做了生成缓存）。

但 Godot 2D 的绘制命令会被**每帧重新遍历、重新合批、重新提交 GL draw call**。
而 CanvasItem 的可见性裁剪**只到节点级 AABB**：整条轨道是**一个** CanvasItem，
其 AABB 覆盖全关卡（约 12000×2000px），**永远判定为可见**。

结果：每帧把 ~667 个多边形全部提交，而屏幕上真正可见的只有
`1280px / 18px ≈ 71` 个 → **约 90% 是纯浪费**。
微信端这些指令还要走 JS→WASM→WebGL 调用链，开销被进一步放大。

### 与文档不一致的缺口

`platform_config.gd` 的注释写明"性能靠 30Hz 背景/障碍、关闭全屏后处理和**屏幕外裁剪**"，
但轨道层**并未实现任何裁剪**。这是文档承诺与代码实现的落差。

### 修法

把 `TrackRenderer` 拆成**按空间分块的多个 CanvasItem**（例如每 1024px 一块，或按 piece 分组），
每块有独立的小 AABB → Godot 自动裁掉屏幕外的块。
预期轨道 draw call 降到 **~10%**。分块边界需处理跨块 piece（让相邻块各画一份，或用 `_piece_quads_cache` 按块索引）。

---

## 四、根因 C：SkyBackdrop 单次 `_draw()` 约 300~400 个指令

### 证据（`sky_backdrop.gd:143`）

| 绘制内容 | 指令数 |
|---|---|
| `_draw_sky()` 渐变带 + 光晕 | 72 + 10 = **82** 个 `draw_rect` |
| `_draw_sun()` | 7 个 `draw_circle` + **12** 条 `draw_line` |
| `_draw_clouds()` | 5 朵 × 6 = **30** 个 `draw_circle` |
| `_draw_mountains()` | 2 条山脊，每条 `for x in range(-40, width+60, 14)` ≈ 95 点<br>→ 2 个 `draw_colored_polygon(95点)` + **逐点** `draw_line` ≈ **190** 条 |
| `_draw_foreground()` | 地面多边形 + 边缘 polyline |
| 背景特效（snow） | `150 × 0.4` = **60** 个 `draw_circle` |

**合计 ≈ 300~400 个指令**，微信档 `background_render_hz = 30` → **每秒约 10000~12000 次顶点生成 + 对应 draw call**。

`_draw_theme_park()` 在 `game_mode` 下 return（`:143` 附近），关卡内已跳过 ✓

### 为什么这块特别亏

SkyBackdrop 是**全屏 Control**，AABB 恒等于视口 → **每帧必然可见、必然全量提交**，无法被裁剪救回。
而天空渐变、山脊、太阳这些内容**在 33ms 内几乎不变**（只有 `_auto_scroll` 与 `_time` 驱动缓慢视差）。

### 修法

把静态部分（天空渐变、山脊、太阳、云、地面）**一次性烘焙成纹理**
（`SubViewport` → `ViewportTexture`，或直接 `ImageTexture`），
运行时只做 1 次 `draw_texture_rect` + 视差平移；只有粒子/动画元素保留动态绘制。
预期从 ~350 指令降到**个位数**。

注意包体预算：烘焙是**运行时生成**，不占 PCK 体积，但要占显存
（1280×720 RGBA ≈ 3.7MB，微信端可接受）。

---

## 五、根因 D：缆车每物理帧强制重绘两个 CanvasItem

### 证据（`coaster_controller.gd`）

- `:513-514` `_physics_process` **开头无条件** `_wheel_layer.queue_redraw()`
- `:587` **结尾无条件** `queue_redraw()`
- `:526` 即使 `not active`（非玩家控制）也 `queue_redraw()`
- 全文件 `queue_redraw()` 共 **14 处**（`:226,228,296,326,328,369,404,445,495,506,514,526,587,621,656,830,847,854,861`）

### 每帧重建的内容

**`_draw()`（`:949-993`）：**
- 冲刺拖尾：`segment_count + 1`（默认 `dash_trail_segments = 16`，`:130`）→ 17 点的 `draw_polyline_colors` + `draw_circle`
  （仅在 `dash_fade > 0.01` 时绘制，常态关闭 ✓）
- 护甲环：`draw_arc(48 点)` × 2
- 车身交给 `BodySprite` 子节点 ✓

**`draw_wheels()`（`:256-274`）：**
- 每轮（默认 2，最多 4）：`draw_texture_rect` + 1 条吊杆 `draw_line`
- 无贴图兜底：3×`draw_circle` + 4×辐条 `draw_line`

### 代价

Godot 2D 的 `_draw()` 指令是 **CPU 端每帧重建顶点数组并上传 GPU**。
60 物理帧/秒 × 2 个 CanvasItem = **每秒 120 次完整顶点重建**。
微信端单线程（`variant/thread_support=false`）无 RenderThread，这部分**全部压在主线程**。

而常态下每帧重绘的实际内容是护甲环 + 车轮 + 吊杆——
**这些在车身姿态不变时完全没有重建的必要**。

### 修法

- 改为**脏标记**：只在姿态/护甲/冲刺状态变化时 `queue_redraw()`
- 车轮旋转改用**子节点 `Sprite2D` + `rotation`**（GPU 变换，零 CPU 顶点重建），
  `_wheel_spin`（`:586`）直接写子节点 `rotation` 即可
- 护甲环、拖尾拆成独立子节点，仅激活时 `visible = true` + 重绘

---

## 六、根因 E：轨道几何热点函数复杂度不合理

### 每物理帧的固定开销

| 函数 | 复杂度 | 调用点 |
|---|---|---|
| `slope_at(s)` | 内部 `tangent_at` → **2× `sample_at`** | `:536` |
| `_update_pose()` | 1× `sample_at`（`:898`）+ `angle_at` → `tangent_at` → **2× `sample_at`** | `:585` |
| `piece_index_at_s(s)` | **O(n) 线性遍历**（n ≤ 300） | `:520` |

= **5 次二分查找 + 1 次 300 项线性扫描**，每物理帧。GDScript 解释执行下不便宜。
`sample_at` 本身是二分（廉价），但一帧调 5 次仍是浪费——`_update_pose` 完全可以一次采样同时得到 position 和 tangent。

### 更严重：`get_track_runs()` 每帧可能重建 2~3 次

`track_geometry.gd` 中这些函数**内部各自调用 `get_track_runs()` 重建 `Array[Dictionary]`**：
- `run_has_gap_at_start()`（`:148`）← 缆车 `:578` 调用
- `run_has_gap_at_end()`（`:160`）← 缆车 `:572` 调用
- `get_run_anchor_piece()`（`:456`）、`is_isolated_piece`（`:435`）、`run_index_for_piece`（`:444`）、`get_run_endpoints`（`:480`）

缆车到达 run 端点的那一帧会连续走 `run_has_gap_at_end` + `_is_open_global_end` + `run_has_gap_at_start`
→ **单帧重建 runs 数组 2~3 次**。GDScript 里 Array/Dictionary 分配直接产生 GC 压力，
**微信端 WASM 堆上的 GC 停顿就是肉眼可见的掉帧尖刺**——这也解释了"卡在特定位置"的现象。

> 正面例子：`coaster_controller.gd:304` 在 configure 时缓存了 `_runs`，`:567` 用缓存 ✓
> 但 `:381` `_perform_blink()` 里又 `for run in track.get_track_runs()` 重新拉取 ✗

### 飞跃断口时的最坏情况

`_advance_flight`（`:626`）：
- `:637` `steps = clampi(..., 1, 8)`
- 每步 `track.nearest_rail_s(probe)` + `track.sample_at(candidate_s)`
- `nearest_rail_s` 是 **O(points) 全遍历 ≈ 1000 段**，且内部对每段调
  `gap_segments.has(index)` 和 `is_piece_broken`——**`Array.has()` 是 O(m) 线性查找**

→ 飞行时每物理帧最坏 **8 × 1000 × 线性 has** ≈ 数万次比较。
**这就是"飞跃断口时突然卡一下"的元凶。**

### 修法

1. `get_track_runs()` 在 `build()` 后算一次存 `_runs_cache`，所有内部调用改用缓存
2. `piece_index_at_s` 改二分（`piece_ranges` 的 `start_s` 单调递增）
3. `gap_segments` / `broken_pieces` 从 `Array` 改 `Dictionary`（当 set 用）或 `PackedByteArray` 位图，`has()` 从 O(m) 降到 O(1)
4. `nearest_rail_s` 加**空间网格索引**（points 按网格分桶），飞行吸附从 O(1000) 降到 O(几十)
5. `_update_pose` 一次采样同时算 position + tangent，把每帧 5 次二分压到 2 次

---

## 七、根因 F：纹理压缩与平台不匹配（纯收益，无代价）

- `project.godot`：`textures/vram_compression/import_etc2_astc=true`
- 导出预设 `export_presets.cfg` preset.1 "Web / WeChat"：
  `vram_texture_compression/for_desktop=true`、**`for_mobile=false`**

微信小游戏跑在**手机 GPU**（Adreno/Mali/PowerVR）上，S3TC/DXT/BPTC 在移动端 GLES3
**不是必需支持**的格式。结果：

- 纹理被驱动**软解成 RGBA8** 再上传（内存翻倍 + 上传耗时），或 fallback 到未压缩 → **显存暴涨**
- 微信小游戏内存上限严格（iOS 约 1GB，超限直接被杀），显存压力触发系统级 GC 与纹理重上传
  → **随机性大卡顿**

**修法：** preset.1 改 `vram_texture_compression/for_mobile=true`。与帧率/DPR 无关，**零体验损失**。

---

## 八、根因 G：WebGL 上下文属性偏保守（模板默认值）

`build/wechat/godot-loader.js:101-117` `initWebGL()`：

| 属性 | 当前值 | 问题 |
|---|---|---|
| `preserveDrawingBuffer` | `true` | 强制每帧保留后缓冲，**阻止手机 GPU 的 TBDR 优化**，额外触发全屏 resolve/copy。加载页需要它，引擎接管后不需要 |
| `depth` | `true` | 纯 2D 游戏（`gl_compatibility` 的 2D 路径）**不需要深度缓冲**，移动端多一个 attachment 就多一份带宽 |
| `renderViaOffscreenBackBuffer` | `true` | 渲染到离屏再 blit，**多一次全屏拷贝** |
| `explicitSwapControl` | `1` | 与上条配合的手动 swap |

全屏拷贝量级：`1280 × 720 × 1.5² ≈ 2.07M` 像素/帧。

这些是 GodotHub `godot-minigame` 模板为兼容加载页而设的默认值。
对纯 2D 游戏，`preserveDrawingBuffer:false` + `depth:false` 在 TBDR 手机上通常有 **10~20% 帧时间收益**。

> **改前必须验证：** 加载页用自己的 program 画全屏 quad（`godot-loader.js` 的 `render()`），
> 改成 `preserveDrawingBuffer:false` 后需确保它在同一帧内完成 draw + commit，否则加载页会黑屏。

---

## 九、次要开销（已核实，量级较小）

### 已排除的嫌疑（原判断有误，此处更正）

1. **20 个 autoload 在关卡内无常驻每帧回调**
   - `ui_theme.gd:78` 的 `_process` 已被 `ui_theme.gd:37` `set_process(false)` 关闭
     （注释说明"颜色覆盖在节点加入时已写入；不再每帧 `find_children` + `queue_redraw`"）
   - `ui_juice.gd:221` 仅当 `_popup_anims` 非空时运行，空时 `:223` 自关
   - `telemetry_service.gd:42` 有早退（`:44` 判 `_backend == null or not has_pending()`）
   - `scene_router.gd:58` 仅 `_loading_active` 时执行
   - 其余 15 个（含 `audio_director`、`analytics_service`、`community_service`、`api_client`、
     `adaptive_difficulty_service`、`developer_service`）**根本没有 `_process`**
   - → **关卡内常驻每帧回调 = 2 个**：`game_controller.gd:167` + `coaster_controller.gd:510`，
     外加 N 个屏幕内障碍

2. **网络请求不阻塞主线程**
   - `api_client.gd:45` `HTTPRequest.new()` → `:52` `request()` → `:62` 连 `request_completed` 信号，**完全异步无 await**
   - `community_service.gd:257` `submit_score` 仅在关卡结束时调 1 次（`game_controller.gd:727`）
   - `analytics_service.gd` 无 `_process`、无 Timer，仅 UI 主动调用时触发

3. **音频无每帧轮询**
   - `audio_director.gd` 无 `_process`；`:50-56` 预创建 **10 个** `AudioStreamPlayer`，
     `:29-36` 在 `_ready` 一次性合成缓存到 `_streams`；播放是 `stop()` → 赋值 `stream` → `play()`（`:243-247`），
     **不重新加载流、不创建新节点** ✓ 这个设计很好

4. **障碍层已是好模式**
   - `obstacle.gd:578` `_refresh_overlay_redraw()` 用 `_overlay_signature` 字符串比对，
     **状态不变时不 `queue_redraw()`**（`:584` 早退）
   - `obstacle.gd:1053` `_draw()` 只画调试触发环：2 个 `draw_arc(24 点)`，且常态下 `has_visual` 判定后直接 return
   - `obstacle.gd:605` `_animation_duration()` 的调用点（`:596,602,629,967`）**全是相位/状态切换时**，
     受 `_interval_phase_time <= 0.0` 守卫，**不是每帧调用**（原怀疑有误）

5. **触摸输入链路干净**
   - `touch_controls.gd:107` `_input` 事件驱动，`_pad_at()` 只遍历 2~4 个按钮
   - `touch_pad.gd:11-16` `active` setter 有 `if active == value: return` 守卫，**仅状态变化时重绘** ✓
   - 刻意不用 `Button`（`:3-5` 注释：Godot 触摸模拟鼠标同一时刻只支持一根手指）——这个判断是对的

6. **障碍空间剔除已生效**
   - `game_controller.gd:316` `_update_obstacle_activity`，`:320` 间隔 0.2s，`:324` 范围 1200px
   - 屏幕外调 `obstacle.set_offscreen_paused(true)`（`:334`）→ `obstacle.gd:738` `set_process(false)`
   - 注释明确："长关卡里 90% 的障碍都在屏幕外"

### 确实存在的次要成本

7. **`meteor_trail.gd` 每帧无条件重绘** —— 关卡内**除缆车外唯一**的每帧重绘源
   - `:58 / :65 / :75` 三条路径全部 `queue_redraw()`，无脏标记
   - `_draw()`（`:138`）：`trail_segments`（默认 1，上限 24）个 `draw_polygon` + N 个火星 `draw_circle`
   - 火星数 ≈ `ember_lifetime × ember_spawn_rate(16) × meteor_fx_scale(0.6)`
   - **缓解因素：** 它是流星障碍的子节点，屏幕外障碍已被 `set_process(false)` 剔除，
     同屏流星通常仅 1~2 个 → 量级有限，**优先级低于缆车**

8. **`game_hud.gd:119` `update_run()` 每次生成新字符串**
   - 单次仅 3 处赋值（`meter.set_values`、`progress.value`、`time_label.text`）→ 很轻
   - 但 `:113-115` `_format_timer` 每次都 `"%s/%s" % [...]` 格式化 → 12Hz（`hud_update_hz`）下
     每秒 12 次字符串分配 + 中文字体 shaping。量级小，可加"文本未变则跳过"守卫

9. **`game_controller.gd:541` `_update_meteor_feedback` 每帧跑**
   - 含 `lerpf` + `ColorRect.visible` 切换 + `Color` 构造
   - 常态下 `_meteor_target_shake = 0`，**可以早退**

10. **`_spawn_floating_text`（`game_controller.gd:785`）每次新建 Label + Tween**
    - 触发点 `:595,645,661`（得分/护甲抵消/通关失败）
    - 碰撞频繁时是尖刺源；`UITheme.body_font` 中文字体光栅化在微信端较贵
    - 全项目 `create_tween` 共 **23 处**，高频碰撞时可能同时存在 5~10 个 Tween
      （引擎侧 C++ 更新，开销远低于脚本回调，**非主要瓶颈**）

11. **`obstacle.gd:612-613` 遍历 SpriteFrames 全部帧累加 duration**
    - 虽非每帧调用，但每次相位切换都重算 → 可缓存，优先级最低

---

## 十、平台配置事实备忘

### `PlatformConfig` 微信档（`platform_config.gd`，已核实）
```
max_fps = 60                    max_device_pixel_ratio = 1.5
background_render_hz = 30.0     hud_update_hz = 12.0
atmosphere_blur_enabled = false atmosphere_pass_enabled = false
background_particle_scale = 0.4 obstacle_visual_hz = 30.0
obstacle_contact_hz = 20.0      meteor_fx_scale = 0.6
level_fullscreen_fx = false     allow_fullscreen = false
```
末尾 `Engine.max_fps = max_fps`。注释："保持清晰度：DPR 1.5；性能靠 30Hz 背景/障碍、关闭全屏后处理和屏幕外裁剪"

### `export_presets.cfg` preset.1 "Web / WeChat"
```
custom_features = "wechat"      export_path = "build/web/index.html"
variant/thread_support = false  variant/extensions_support = false
html/canvas_resize_policy = 2   threads/emscripten_pool_size = 8
vram_texture_compression/for_desktop = true
vram_texture_compression/for_mobile  = false   ← 见根因 F
```

### `project.godot`
```
viewport 1280×720   stretch/mode = "canvas_items"   aspect = "expand"
handheld/orientation = 4
renderer/rendering_method = "gl_compatibility"（含 .mobile）
default_texture_filter = 0（Nearest）   import_etc2_astc = true
2d_physics/layer_1..6 = World/Coaster/Obstacle/PassengerPickup/FinishGate/Touch
【无 [physics] 段】← 见根因 A
```

### 关卡数据规模
- 最大 `level_35.json` 61.3KB、`level_43.json` 60.8KB、`level_44.json` 54.1KB、`level_45.json` 43.8KB
- `level_01` `finish_s ≈ 8005.74`、`level_03 ≈ 11907.79`、`level_04 ≈ 12755.17`
- 折线采样：直线 `MAX_STEP := 14.0`、圆弧步长 12.0 → **12000px 轨道 ≈ 900~1000 个采样点**
- `MAX_PIECES := 300`、`MAX_TOTAL_LENGTH := 120000.0`、`catalog.json` 列 45 个内置关卡

### 微信包体
- `engine` 分包约 12.67MB：`godot.wasm.br` 6,240,533 B / `game-pck.bin` 6,074,780 B / `godot.js` 349,351 B
- 中文字体已子集化到 2.23MB
- 启动链：`engine.init('/engine/godot')` → `waitForEngineSubpackage()` → `readPackageFile('/engine/game-pck.bin')`
  → `engine.preloadFile(...)` → `loader.cleanup()` → `engine.start({args:['--main-pack', pack]})`
- DPR 生效：`GameGlobal.__platformMaxDpr = 1.5`（`build/wechat/game.js`）
  → `godot-loader.js` `getDevicePixelRatio()` 取 `wx.getWindowInfo().pixelRatio` 与 `__platformMaxDpr` 较小值并重写 `window.devicePixelRatio`

---

## 十一、实施顺序建议

### 第一批：零风险纯收益（先做，可立即验证）
1. `export_presets.cfg` preset.1 → `vram_texture_compression/for_mobile=true`（根因 F）
2. `game_controller.gd:541` `_update_meteor_feedback` 加早退（次要 9）
3. `track_geometry.gd` 的 `gap_segments`/`broken_pieces` 改 Dictionary/位图（根因 E-3）
4. `get_track_runs()` 结果缓存（根因 E-1）

### 第二批：解决卡帧移动（核心，需仔细验证）
5. 开启 `physics/common/physics_interpolation=true`
6. 按第二节表格逐个设置 `physics_interpolation_mode = OFF`
7. 缆车瞬移处补 `reset_physics_interpolation()`
8. **真机验证：** 录屏逐帧比对位移方差

### 第三批：砍渲染大头（工作量大，收益最大）
9. 轨道分块 + AABB 裁剪（根因 B）
10. SkyBackdrop 静态部分烘焙成纹理（根因 C）
11. 缆车改脏标记 + 车轮转子节点 Sprite2D（根因 D）

### 第四批：算法与平台
12. `piece_index_at_s` 二分、`nearest_rail_s` 空间网格、`_update_pose` 复用采样（根因 E）
13. WebGL 上下文属性调优（根因 G，需先验证加载页）

### 验证手段
- 微信开发者工具 → 真机调试 → Performance 面板，看 scripting / rendering 时间分布
- 在 `PlatformConfig` 加临时帧时间统计（`Engine.get_physics_frames()` + `Time.get_ticks_usec()`），输出到 HUD 或 `console.log`
- **关键指标：** 缆车每帧位移像素的**方差**（方差大 = 卡帧移动），比平均帧率更能反映手感
- 用 `Performance.get_monitor(Performance.RENDER_2D_DRAW_CALLS_IN_FRAME)` 对比轨道分块前后的 draw call 数

---

## 十二、待确认项（需要用户决策或提供实测数据）

1. **目标机型集合**（低端安卓占比）与**真机 vs 开发者工具的帧率差距实测数据**
   —— 决定 P0 之后还要压多少渲染量
2. **关卡内实际 `points.size()` 分布**（需运行时打印确认，本文按 `finish_s / MAX_STEP` 估算）
3. **是否接受"静态轨道烘焙成贴图 + 局部刷新"的重做幅度**（根因 B 的替代方案，收益更大但改动更深）
4. 是否存在可复用的**分块 LOD / 视口裁剪基础设施**
5. **触摸输入事件在微信 WebView 的实际派发频率**（可用临时计数器测量）
   —— 若派发频率本身抖动，P0 之外还需输入预测
6. 是否允许对**空中吸附的扫掠步数上限**进一步收紧（当前 `coaster_controller.gd:637` clamp 到 8）
7. **双人分屏模式**是否也需要同样的微信档（本文聚焦单人关卡内；`duo_game_controller.gd:206` 的相机也需插值豁免）
8. 结算阶段网络提交（排行榜/社区）是否会阻塞主线程导致退出卡顿
   —— 已核实 `api_client.gd` 为异步，**基本可排除**，但真机可复测

---

## 附：本次分析修正的历史误判

为避免后续优化走弯路，记录三处**与原判断相反**的核实结果：

| 原判断 | 核实结果 |
|---|---|
| 20 个 autoload 每帧有 4+ 个 GDScript 回调 | **0 个常驻**，全部有 `set_process(false)` 或早退守卫 |
| 障碍 `_animation_duration()` 高频调用造成尖刺 | 受 `_interval_phase_time <= 0.0` 守卫，**仅相位切换时调用** |
| 障碍层每帧重绘 | `obstacle.gd:584` 有 signature 脏标记，**状态不变不重绘** |

同时确认了两处**原以为有问题、实际设计良好**的地方：
音频节点池预创建（`audio_director.gd:50-56`）、触摸层刻意避开 `Button`（`touch_controls.gd:3-5`）。
