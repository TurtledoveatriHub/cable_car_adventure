# 微信端性能优化 — 实施清单（执行中）

> 配套分析见 `docs/WECHAT_PERF_ANALYSIS.md`。本文件是落地施工图，含已核实行号。
> 用户授权：不破坏主观体验的优化全部可做；无负面影响的改动全端生效，不限微信。

---

# ★ 进度快照（压缩前固化，勿删）

## 官方文档核实结论（Godot 4.5 Node 类文档，已联网确认）
- `physics_interpolation_mode` **只有在** `ProjectSettings.physics/common/physics_interpolation`
  或 `SceneTree.physics_interpolation` 为 true 时才生效 → **全局开关必须打开，节点级 ON 无法独立生效**。
- 枚举：`PHYSICS_INTERPOLATION_MODE_INHERIT = 0`（新节点默认）、`ON = 1`（根节点默认）、`OFF = 2`。
  OFF 同时对「设为 INHERIT 的子节点」生效 → **父节点设一次即覆盖全部子节点**。
- `reset_physics_interpolation()`：**必须在移动节点之后调用**（已遵守）；递归发通知给子节点。
- `reparent()` 警告：开插值后若 reparent 造成 global transform 大幅变化会滑行，需调 reset。
- 插值教程页：「在物理帧之外设置已插值对象的变换 → 插值计算错误并产生抖动」；
  「间接移动（tween/animation/navigation）也必须是物理帧时序」；建议临时降到 10 TPS 暴露问题。

## ✅ 已完成的改动（全部已 Edit 成功）
1. **`project.godot`** — `[layer_names]` 与 `[rendering]` 之间新增 `[physics]` +
   `common/physics_interpolation=true`（文件现 85 行，段落在 `:74-76`）。
   ⚠️ 第一次 Edit 误产生重复段落，已清理并 Read 复核干净。
2. **`export_presets.cfg:96`** — `vram_texture_compression/for_mobile=false` → `true`（已复核）。
3. **`game_controller.gd`**（现 932 行）
   - `_process`（`:167`）现只剩 `_update_meteor_feedback(delta)` + phase match + `_update_obstacle_activity(delta)`。
     已移出：`_update_shake`、`_update_camera`、`backdrop.camera_x`。
   - 新增 `_physics_process(delta)`（`:187`），同一套守卫
     （`get_tree().paused or _paused or _result_sent or level == null` → return），
     内含 `_update_shake(delta)` → `_update_camera(delta)` → `backdrop.camera_x = camera.global_position.x`。
     理由：缆车位置在 `_physics_process` 写入并被插值，相机须共用同一插值因子，否则「游动」。
   - `:296` `camera.global_position = _get_camera_target()` 后加 `camera.reset_physics_interpolation()`。
   - 已 Grep 确认全文件**只有一个** `_physics_process`（`:187`），无重复定义。
   - 相机写入点：`:220` zoom、`:296` global_position、`:518/525` `_update_camera`、`:534` offset。
4. **`obstacle.gd:169` `_ready()`** — 首行加
   `physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF`（+3 行注释）。
   覆盖 Visual / PlayerDetector / Frame / CabinSlots / MeteorTrail / FerrisWheelVisual 全部子节点。
   依据：障碍在 `_process`（`:472`）→ `_update_position`（`:1037`）写 `global_position`。
   `obstacle_bullet.gd` 是 `extends Area2D` 独立类，但在 `_physics_process`（`:69`）写
   `global_position`（`:89`）→ **正确用法，保持插值 ON，不要豁免**。
5. **`passenger_eject.gd`** — 新增 `_ready()` 设 OFF。依据：`_process`（`:34`）积分 `position`/`rotation`。
6. **`teleport_sparkle.gd:20` `_ready()`** — 首行加 OFF。依据：位置在输入回调（物理帧外）一次性写入。
7. **`coaster_controller.gd`**（现 1006 行）
   - `hide_mirror_collision()`（`:456`）首行加 OFF —— 三个幽灵/镜像缆车
     （`_shared_p2_cart`、`_split_p2_ghost`、`_split_p1_ghost`）的统一初始化入口，一处覆盖全部。
     依据：位置由 `duo_game_controller._process` → `sync_visual_from` 在渲染帧写入。
   - `_perform_blink`（`:398-402`）：`current_s = target_s` → `_update_pose()` → `reset_physics_interpolation()`。
     依据：由 `_input` → `_register_dash_tap`（`:356-362`）触发，在物理帧之外。
   - `_begin_flight`（`:621`）：`global_position = exit_point` → `reset_physics_interpolation()`。
   - 三处 tween 加 `tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)`：
     座位 animate 分支（`:764`）、`_animate_boarding`（`:779`）、`_animate_alighting`（`:815`）。
     这些 tween 移动座位 `Sprite2D.position`，座位继承缆车插值。时长/缓动/delay 未改。

## ⏳ 尚未完成（按优先级）
- **A 剩余 1**：`duo_game_controller.gd` 的 `_update_shared_camera()`（`:186-207`，写
  `game1.camera.global_position` 与 `zoom`）仍由 `_process`（`:82`）调用 → **必须移到 `_physics_process`**。
  shared 模式下 `game1.external_camera_control = true`（`:37`），game_controller 的
  `_update_camera` 会早退，不冲突；但其 `_physics_process` 里的 `_update_shake`/`backdrop.camera_x` 仍会跑，无害。
  `_update_shared_visual`（`:182`）/`_update_split_ghost`（`:173`）调 `sync_visual_from` 写幽灵位置
  —— 幽灵已豁免 OFF，**无需改动**。
- **A 剩余 2**：✅ 已完成 —— 改为在 `game_controller._ready()`（`:126`）对 `fx_root` 整层设
  `PHYSICS_INTERPOLATION_MODE_OFF`（Fx 层只承载浮动文字，IDLE 补间在渲染帧写 position）。
- **E1**：✅ 已完成 —— `_update_meteor_feedback` 加早退（四量全零且色块已隐藏时 return）。
- **C 组**：✅ 已完成 C2/C3/C4/C5；**C1 无需改动**（`_find_segment` 本来就是二分）；
  **C6 网格索引主动放弃** —— 位图化已消除 `nearest_rail_s` 内层 O(N×G) 瓶颈，
  网格索引边际收益低且有改变磁吸落点的风险。
  新增内部只读索引：`_gap_mask` / `_broken_mask`（PackedByteArray 位图）、
  `_piece_start_s` / `_piece_end_s`（预计算区间）、`_runs_cache`（get_track_runs 缓存）。
  失效点：`build()` 开头清空全部索引并置 `_runs_cache_valid=false`，
  末尾按 `_rebuild_cumulative` → `_rebuild_segment_pieces` → `_rebuild_indices` 顺序重建；
  `break_piece` / `reset_breaks` 同步维护位图与公开数组。**公开字段仍是唯一真相来源。**
  `piece_index_at_s` 二分完整保留原兜底语义：落在空档（无片段覆盖）时返回最后一个片段。
- **D 组**：✅ 完成按需重绘 + **D4 副作用搬迁（正确性修复）**。
  `_draw()` 里原先写 `body_sprite.rotation` / `bg_sprite.rotation` / `bg_sprite.flip_h`
  —— 这是「渲染帧写已插值子节点变换」，与全局插值直接冲突，已搬到新增的
  `_sync_body_visuals()`（在 `_physics_process` 最前调用，且在 `track == null` 判空之前，
  以保留原「缺纹理时 push_error 一次」的行为）。只在倾角/翻转真变化时写子节点。
  新增 `_update_redraw_flags()`：拖尾活跃或刚结束那一帧、装甲环可见性或 `body_offset_y` 变化、
  车轮轨道角变化（无贴图时另判 `_wheel_spin`）才置脏；`_mark_visual_dirty()` 供状态突变强制刷新。
  已去掉的每帧无条件重绘：`_physics_process` 顶部的 `_wheel_layer.queue_redraw()`、
  地面移动末尾（原 `:593`）与 `not active` 分支（原 `:532`）的 `queue_redraw()`。
  **D 组未完成部分**：车轮改 Sprite2D 子节点（工作量大，且需处理
  `_capture_child_base_positions` / `_apply_visual_settings` 的整体平移排除逻辑）。
- **F1**：✅ 已完成 —— `_draw_ridge` 亮边改 `draw_multiline`（约 190 次 draw_line → 2 次），
  线段集合/颜色/线宽/抗锯齿完全一致。**F2 天空渐变分层未做**：72 band 用的是
  `pow(ratio, 0.82)` 非线性插值，且 `_draw_sky` 与太阳/云/山脉同处一个 `_draw()`，
  拆子 Control 会遮挡太阳与云，需改为缓存纹理方案，风险与工作量都更高。
- **G**：❌ 未开始 —— `track_renderer.gd` 轨道分块裁剪（需先补读 `:1-52`、`:310-477`）。
- **额外完成（原清单外，属插值正确性必需）**：
  - `duo_game_controller.gd`：`_update_shared_camera()` / `_update_offscreen_markers()` 从
    `_process` 移到新增的 `_physics_process`（共享相机写 `game1.camera.global_position`/`zoom`）。
  - `track_fx_layer.gd` `_ready()` 设 OFF —— 预警层 position 由 `track_renderer._process` 在渲染帧写。
  - `obstacle_bullet_emitter.gd:100` 子弹出膛后加 `bullet.reset_physics_interpolation()`
    —— 子弹来自对象池，不重置会从上次位置滑行到新枪口。
  - `start_gate.gd` / `finish_gate.gd` `_ready()` 设 OFF —— 两者只在 `configure()` 定位一次，
    保持插值会从原点 (0,0) 滑行到轨道位置。物理插值只影响渲染变换，
    **不参与 Area2D 判定，碰撞精度不变**。
- **验证**：`--headless res://tests/test_runner.tscn` → **168 项全部通过，退出码 0**（跑了 3 次）。
  覆盖玩法移动、重力、障碍伤害、乘客归零失败、断裂脱轨、终点结算、存档、
  双人分屏/共享、暂停冻结、全部 45 关序列化、车轮层级、UI 绑定。
  测试输出中的 `WARNING: Camera2D overridden to physics process mode due to use of
  physics interpolation` 反向证明相机时序迁移是必需的，且全局插值已真实生效。
- 子代理不可用（membership_paywall 中断两次），全部改动自己完成。

## 硬约束
- `max_fps = 60`、`max_device_pixel_ratio = 1.5` 不得下调
- 碰撞判定精度不得下降；视觉降频不得影响判定
- 渲染后端保持 `gl_compatibility`；Web 导出保持单线程

---

## A. 物理插值（P0，解决"卡帧移动"）

**A1. `project.godot`** — 当前无 `[physics]` 段（`:65-72` 是 `[layer_names]`，`:74-80` 是 `[rendering]`）。
在两段之间插入：
```
[physics]

common/physics_interpolation=true
```

**A2. 豁免清单**（凡在 `_process` 里直接写 `global_position` 的节点，开插值后会额外滞后一帧，必须设
`physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF`）：
- `game_controller.gd` 相机（`:516` `camera.global_position += move * follow`，在 `_update_camera`，由 `_process:167` 调）
  → 在 `_ready()`（`:121`）里对 `camera` 设置 OFF
- `duo_game_controller.gd:206` `game1.camera.global_position = ...lerp(target, 0.16)` → 双人相机同样 OFF
- `obstacle.gd` 移动障碍（`:1038` `global_position = _position_at_progress(...)`）+ 全部瞬移点
  （`:259,715,745,764,779,794,803,1002,1018,1027`）→ 在 `_ready()` 里对 self 设 OFF
- `passenger_eject.gd:24` 瞬移 → self 设 OFF
- `meteor_trail.gd`、`ferris_wheel_visual.gd`、`teleport_sparkle.gd` 纯视觉 → self 设 OFF

**保持插值 ON 的只有缆车本体**（`coaster_controller.gd`，位置在 `_physics_process:585` → `_update_pose:898` 写）。

**A3. 缆车瞬移处补 `reset_physics_interpolation()`**（否则会插值出一段滑行残影）：
- `coaster_controller.gd:491` `global_position = source.global_position`（双人镜像同步）
- `coaster_controller.gd:614` `global_position = exit_point`（`_begin_flight` 起飞吸附）
- `_perform_blink()` 传送路径（`:400` 附近，`current_s` 被改写后紧跟 `_update_pose`）
- **不要**给 `:898`（`_update_pose` 正常行驶写入）加，那是插值的正常输入

**A4. 验证**：录屏逐帧比对"缆车每帧位移像素"的方差，应从剧烈波动降到接近 0。

---

## B. 导出预设纹理压缩（纯收益）

`export_presets.cfg:96` `vram_texture_compression/for_mobile=false` → `true`

原因：手机 GPU（Adreno/Mali/PowerVR）不支持 S3TC/BPTC，当前纹理被软解成 RGBA8，
显存翻倍 → 微信 iOS ~1GB 内存上限下触发系统级 GC 与纹理重上传 → 随机大卡顿。

**需告知用户**：同时保留 `for_desktop=true` 会让纹理含两份压缩格式，`game-pck.bin`（当前 6,074,780 B）
体积会上升。若要省包体可把 `for_desktop` 关掉（WebGL2 强制支持 ETC2，PC 浏览器仍可用）。

---

## C. `track_geometry.gd` 算法与内存（低风险，全部可做）

文件 524 行。已核实的关键位置：

**C1. `_find_segment`（`:359-370`）加局部性 hint** ← 零行为差异，收益最大
缆车连续移动时每帧 `s` 只变一点，段索引几乎不变。当前每次调用都跑二分（~10 步），
而 `_physics_process` 每帧经 `slope_at`(`:536`) + `_update_pose`(`:585`→`:898,899`) 触发 **5 次** `sample_at`。
改法：新增 `var _last_segment_hint: int = 0`，先检查 hint / hint±1 是否命中区间，命中直接返回，
否则回退原二分并更新 hint。`build()`（`:45`）里重置 hint = 0。

**C2. `piece_index_at_s`（`:198-204`）改二分 + 预计算数组**
当前 O(n) 线性遍历 `piece_ranges`（n ≤ 300），且每次从 Dictionary 取值（GDScript 里很慢）。
`_physics_process:520` 每帧调一次。
改法：`build()` 末尾预计算 `_piece_starts: PackedFloat32Array` / `_piece_ends: PackedFloat32Array`
（从 `piece_ranges` 的 `start_s`/`end_s` 抽出，`_rebuild_cumulative`（`:294-300`）之后才有终值），
`piece_index_at_s` 对 `_piece_starts` 二分。
**注意保持原语义**：原逻辑是 `s >= start_s and s <= end_s` 才返回该 index，落空时返回
`clampi(size-1, 0, max(0, size-1))`（即最后一个）。二分实现要保留这个兜底。

**C3. `is_piece_broken`（`:214-215`）改位图**
当前 `broken_pieces.has(index)` 是 **O(m) 线性查找**，而它被 `nearest_rail_s`（`:181`）
在 ~1000 段的循环里每段调用一次。
改法：新增 `_broken_flags: PackedByteArray`，`build()`（`:53` 附近）resize 到 `pieces.size()` 并 fill(0)；
`break_piece`（`:207-211`）置 1 并同步 `broken_pieces` 数组（保持对外语义）；
`reset_breaks`（`:218-219`）fill(0) + clear；`is_piece_broken` 查 `_broken_flags`（O(1)）。

**C4. `gap_segments.has(index)`（`:178`）改 Dictionary set**
同样是 O(m) 线性查找，在 `nearest_rail_s` 的 ~1000 次循环里。
改法：新增 `_gap_segment_set: Dictionary`，`:91` `gap_segments.append(...)` 处同步写入；
`build()`（`:52`）clear；`nearest_rail_s` 用 `_gap_segment_set.has(index)`。
（已 Grep 确认 `gap_segments` / `broken_pieces` **无任何外部引用**，仅本文件内使用。）

**C5. `get_track_runs()`（`:412-432`）加缓存** ← 消除每帧 GC 压力
当前每次调用都重建 `Array[Dictionary]`。内部调用点：
`run_has_gap_at_start:149`、`run_has_gap_at_end:161`、`is_isolated_piece:436`、
`run_index_for_piece:445`、`get_run_anchor_piece:457`、`get_run_endpoints:482`。
外部调用点：`tests/test_fixes.gd:189`、`level_editor.gd:1033,1381`、
`coaster_controller.gd:304`（已缓存到 `_runs`）、`:381`（`_perform_blink`，未缓存）。

缆车到 run 端点那一帧会连走 `run_has_gap_at_end`(`:572`) + `_is_open_global_end` + `run_has_gap_at_start`(`:578`)
→ **单帧重建 2~3 次** → WASM 堆 GC 停顿 = 肉眼可见的掉帧尖刺。

改法：新增 `_runs_cache: Array[Dictionary]` + `_runs_cache_valid: bool`；
`build()` 末尾与 `_rebuild_cumulative()` 后置 `_runs_cache_valid = false`；
`get_track_runs()` 命中缓存直接返回，否则构建并置 valid。
**注意**：缓存的 Dictionary 被外部读取（`level_editor` 会读 `first_piece`/`start_s` 等），
只读不写，可安全共享同一份 Array 引用。

**C6. `nearest_rail_s`（`:172-195`）加空间网格索引** ← 消除飞跃断口卡顿
当前 O(points) 全遍历（~1000 段），`_advance_flight`（`coaster_controller.gd:642`）
每物理帧最多调 **8 次** → 最坏 8000 次迭代，每次还含 C3/C4 的两个 O(m) `has()`。
改法：`build()` 末尾构建 `_grid: Dictionary`（key = `Vector2i` 格坐标，value = `Array[int]` 段索引），
格子边长取 `max(magnet_radius * 2, 64.0)`；查询时只扫 probe 所在格及相邻格。
**保底**：若候选集为空则回退全遍历，保证公开语义（全局最近可落轨点）不变。
调用方 `magnet_radius = 16.0`（`coaster_controller.gd:58`），网格覆盖足够。

---

## D. `coaster_controller.gd` 按需重绘（993 行）

**D1. 护甲环脏标记** ← 常态下 `_draw()` 的主要成本
`_draw()`（`:949-993`）常态下只画护甲环：`:979-982` 两个 `draw_arc(48 点)` ≈ 96 顶点，
而 `armor_radius`/`armor_ring_width`/`ring_center = Vector2(0, body_offset_y)` **全是静态的**。
拖尾（`:962-978`）仅 `dash_trail_enabled and active and dash_fade > 0.01` 时画，常态关闭。
→ 护甲环完全可以只在 `_armor_available` 变化时重绘。

**D2. 去掉 `_physics_process` 里的无条件 `queue_redraw()`**
- `:513-514` 开头无条件 `_wheel_layer.queue_redraw()`
- `:526` `not active` 分支也重绘
- `:587` 结尾无条件 `queue_redraw()`
全文件 `queue_redraw()` 共 14 处：`:226,228,296,326,328,369,404,445,495,506,514,526,587,621,656,830,847,854,861`

**D3. 车轮改 Sprite2D 子节点**（消除每帧顶点重建）
`draw_wheels()`（`:256-274`）当前每帧对每个车轮（默认 2，最多 4）做
`draw_texture_rect` + 1 条吊杆 `draw_line`；无贴图兜底是 3×`draw_circle` + 4×辐条 `draw_line`。
关键事实：**有贴图时 `_wheel_spin` 根本没被用到**（`draw_texture_rect` 是轴对齐矩形，不旋转），
只有无贴图的辐条分支（`:271-273`）用 `_wheel_spin`。
车轮位置 = `_wheel_positions(tangent)`（`:244-253`）= `tangent * lerpf(-wheel_offset, wheel_offset, ratio)`。

改法：有 `wheel_texture` 时改用 N 个 `Sprite2D` 子节点，每帧只写 `position`（N≤4 次 Vector2 赋值，
**零顶点重建**）；无贴图时保留 `_draw()` 程序化路径。
吊杆（`:274`，终点 `Vector2(0, body_offset_y - 16.0)` 是局部固定点）保留在 `_draw()` 里画，N≤4 条线成本很低。

**D3 的坑**：`_capture_child_base_positions()`（`:278-286`）遍历 `get_children()` 记录 Node2D 初始位置，
`_apply_visual_settings()`（`:289-296`）按 `body_offset_y` 差值平移**所有**子节点。
新增的车轮 Sprite2D 必须像 `_wheel_layer` 那样在 `:281-282` 被排除，否则会被误平移。

**D4. `_draw()` 里的子节点副作用**（`:985-989`）
```gdscript
if has_scene_sprite:
    body_sprite.rotation = _failed_tilt
    if bg_sprite != null:
        bg_sprite.rotation = _failed_tilt
        bg_sprite.flip_h = body_sprite.flip_h
```
改成按需重绘后，这段必须移到 `_failed_tilt` / `flip_h` 实际变化时执行，否则车身倾斜会不刷新。
（`:990-993` 尚未读完，实施前需补读。）

---

## E. `game_controller.gd` 小优化

**E1. `_update_meteor_feedback`（`:541-554`）加早退**
每帧跑，含 `Time.get_ticks_msec()`、`Vector2(sin,cos)`、`lerpf`、`Color` 构造。
常态下 `_meteor_target_shake = 0` 且 `_meteor_target_tint = 0` 且 `_meteor_tint_alpha ≈ 0`
→ 三者全为零时直接 return，跳过全部计算。
注意 `:543` 已有 `now - _meteor_report_msec > 120` 的归零逻辑，早退不能破坏它
（归零后正好满足全零条件，可安全 return）。

**E2. `_spawn_floating_text`（`:785`）每次新建 Label + Tween**
触发点 `:595,645,661`。碰撞频繁时是尖刺源。可改为 Label 对象池（低优先级，风险中）。

---

## F. `sky_backdrop.gd` 减少 GDScript 侧 draw 调用（468 行）

单次 `_draw()` ≈ 300~400 个指令，微信档 `background_render_hz = 30` → 每秒约 1 万次顶点生成。
注意：Godot 4 的 CanvasItem 渲染器会自动合批同纹理指令，所以瓶颈是 **CPU 端 GDScript 调用 + 顶点重建**，
不是 GL draw call 数。优化目标是**减少 draw_* 调用次数**。

**F1. `_draw_ridge`（`:312-335`）山顶亮边改 `draw_multiline`** ← 最大单点收益
`:333-335` 当前逐点 `draw_line`，1280 宽 / 14px 步长 ≈ **95 条/山脊 × 2 山脊 = 190 次调用**。
所有线同色 `Color(1,1,1,0.07)`、同宽 2.0 → 符合 `draw_multiline` 要求（每 2 点一条线）。
改法：先收集满足 `absf(dy) > 0.8` 的线段端点对到 `PackedVector2Array`，最后一次 `draw_multiline` 画完。
**严格视觉等价**，190 次调用降到 2 次。

**F2. 天空渐变分层**（`:228-239`，72 band + 10 glow = **82 个 `draw_rect`**）
这部分只依赖 `top_color`/`bottom_color`/`width`/`height`，**完全静态**（云、太阳、山脊才在动）。
改法：SkyBackdrop 内建一个子 Control `_sky_layer`，`_draw()` 只画渐变；
主节点 `_draw()` 不再画天空。`_sky_layer` 仅在 `apply_theme()`（`:111-133`）改色或 `resized` 时重绘。
30Hz 下每秒省 2460 次 `draw_rect`。

**F3. `_draw_soft_ellipse`（`:220-225`）** 24 点多边形，被 `_draw_background_effects`（`:191,208,212`）
在 clouds/forest/paradise 背景反复调用（paradise 6 次、forest 3 次、clouds 12×0.4≈4 次）。
可预生成单位圆点阵复用，省掉每次 24 次 `cos/sin`（低优先级）。

---

## G. `track_renderer.gd` 轨道分块裁剪（477 行）← 工作量最大，收益最大

**问题**：整条轨道是**一个** CanvasItem，AABB 覆盖全关卡（~12000×2000px），永远判定可见。
`_draw_track_texture`（`:215-225`）逐 piece 调 `_draw_piece` → `_draw_piece_texture`（`:282+`）
→ `_get_piece_quads`（`:240-279`，step=18.0）→ `:291-295` 逐 quad `draw_polygon`。
12000px 轨道 ≈ **667 个 `draw_polygon`**，而屏幕可见只有 `1280/18 ≈ 71` 个 → **90% 浪费**。

`set_process(false)`（`:61`）只省掉了 GDScript 重跑 `_draw()`，
但引擎每帧仍要遍历 + 合批 + 提交全部已生成的绘制指令。

**改法**：把轨道按空间分块拆成多个子 CanvasItem（每块 ≈1024px 或按 piece 分组），
每块 `_draw()` 只画自己范围内的 piece → 每块 AABB 自然变小 → Godot 自动裁掉屏幕外的块。

**实施要点**：
- 新增 chunk 层节点数组，`configure()`（`:52-63`）时按 `piece_ranges` 重建
- 主节点 `_draw()`（`:122-183`）保留 `_draw_station()`（`:180`）、`_draw_finish()`（`:181`）、
  `_draw_edit_markers()`（`:183`）与编辑模式选中高亮（`:129-134`）；piece 绘制移到 chunk 层
- 需要传给 chunk 层的状态：`_track`、`_accent`、`_warning_pieces`、`_broken_states`、`_edit_mode`、`_edit_mode` 下的 `_selected_piece`
- `set_warning`（`:74-82`）/ `notify_piece_broken`（`:86-91`）触发的 `queue_redraw()` 要改成只重绘受影响的 chunk
- `_piece_quads_cache`（`:58` clear、`:241` 读）可保留在主节点，chunk 层共享
- **跨块 piece**：按 piece 边界分块（不是按固定像素切），一个 piece 只属于一个 chunk，天然无跨界问题
- 未读完部分：`:1-52`、`:310-477`（`_draw_station`/`_draw_finish`/`_slice_points`/`_piece_points`/
  `_offset_points_from`/`_is_drawable_quad`/`_draw_piece_fallback`/`_draw_edit_markers`）——实施前必须补读

---

## H. 实施顺序

1. **B**（1 行）→ 2. **A**（插值 + 豁免，核心）→ 3. **C**（几何算法）→
4. **E1**（早退）→ 5. **D**（缆车重绘）→ 6. **F**（背景）→ 7. **G**（轨道分块，最后做）

每步做完用 `godot --headless --check-only` 或编辑器加载验证语法，避免累积错误。

## I. 需要用户手动处理的事项（待汇总）
- 重新导出微信包（改了 `export_presets.cfg`）
- 真机验证插值效果
- 决定 `for_desktop` 是否关闭以省包体
