# UGC 上传去重与多端权限 · 事实清单与方案设计

> 本文档由性能优化会话延续而来，记录 UGC 重构所需的全部已核实事实与待确认方案。
> **状态：方案待用户确认，尚未写任何代码。**

---

## 一、渲染优化三模块（已完成，168 项测试通过，退出码 0）

1. **轨道分块裁剪**：新增 `scripts/game/track_chunk.gd`（`TrackChunk`，Node2D，委托回
   `TrackRenderer.draw_chunk()`）。`track_renderer.gd` 以 piece 为原子单位按
   `CHUNK_TARGET_LENGTH=640` 弧长打包成块，每块一个独立 CanvasItem，逐帧按相机视口矩形
   切换 `visible`；`_cull_enabled = not edit_mode`（编辑器看全貌，关闭裁剪）。
   绘制统一收口到 `_draw_pieces_on(target, pieces, assets)`，分块与整轨共用，画面等价。
   删除了已无调用点的 `_draw_track_texture`。预警/断裂改调 `_redraw_static_for_piece()`
   定位所属块重绘。`_process` 自我关闭分支加了 `if not _cull_enabled` 保护。
2. **天空渐变缓存**：`sky_backdrop.gd` 新增 `_get_sky_gradient_texture(height)`，把
   72 色带 + 10 光晕烘成 **1×height** 的 `ImageTexture`（约 3KB，不新增资源文件），
   绘制降为 1 次 `draw_texture_rect` 横向拉伸（渐变只随 Y 变化，横向拉伸无信息损失）。
   缓存键 `"%d|%s|%s" % [pixel_height, top_color.to_html(), bottom_color.to_html()]`，
   `apply_theme` 改写配色时键自动失效。原逐条绘制保留为 `_draw_sky_bands()` 兜底。
3. **车轮**：**放弃 Sprite2D 方案**。理由——上一轮的按需重绘已让 `_wheel_dirty` 只在
   `_track_angle` 变化时置位，直线段根本不重绘，"有贴图时每帧重建"的前提不成立；
   吊杆线仍须留在车轮层 `_draw()`，重绘一次也省不掉，反而凭空多出 4~8 个 CanvasItem
   （双人 16 个），每个都要每帧走裁剪与变换传播，是净亏损。
   改为消除堆分配：`_wheel_local_positions` / `_wheel_pose_positions` 两个长期复用数组，
   只在 `wheel_count` / `wheel_offset` 变化时重建；新增 `_wheel_positions_angle(angle)`
   直接吃角度省掉热路径一次 `atan2`。`_wheel_positions(tangent)` 保留（测试在用）。
   临时创建后废弃的 `cart_wheel_sprite.gd` 已删除。

**注**：新建/删除 `.gd` 带 `class_name` 后必须重新扫描类名缓存，否则无头测试报
`Could not find type "TrackChunk"`（表现为大量连锁失败、检查数从 168 掉到 117）：
`--headless --editor --quit --path <项目>`。
另：PowerShell 管道末尾 cmdlet 会污染退出码，须用 `$out = ... | Out-String; $LASTEXITCODE` 取真值。

---

## 二、UGC 现有链路（已逐处核实）

### 客户端
- `scripts/services/community/community_service.gd`（autoload `CommunityService`）
  - `MAX_LOCAL_UPLOADS := 3`、`LOCAL_STATE_PATH := "user://community/local_state.json"`
  - `upload_level(level_id, display_name, callback)` @`:53`：
    读 `LevelCatalog.get_raw_level(level_id)` → 校验 `SaveManager.is_level_cleared()`
    → 校验上传数 → 违禁词 → `UgcLevelDocument.make_upload_body()`
    → `ApiClient.post_json("/api/ugc/upload", body, cb)`
    → 成功：写 `_details[entry_id]`、`_entries.push_front(entry)`、
      `upload_count += 1`、`_save_local_state()`、`changed.emit()`
  - `_upload_offline(document, clean_name, callback)` @`:359` 测试/离线专用，同样 `upload_count += 1`
  - `:454` 有 `upload_count -= 1` → **存在撤销上传功能**
  - `_author_id()` = `SaveManager.get_player_id()`（稳定展示 id SW-xxxxxx，非 local_player）
- `scripts/services/ugc/ugc_level_document.gd`（`UgcLevelDocument`，静态类）
  - `make_upload_body(raw_level, metadata)` → `{ok, body, size, error}`，body =
    `{name, author_name, author_id, platform, description, level_data}`
  - `_normalize_level(source)` 产出**确定性**规范化字典（字段顺序固定、
    `_round = snappedf(v, 0.001)`、颜色转小写 hex、枚举白名单裁剪）——
    **这是指纹可跨端复现的关键前提**
  - `SCHEMA_VERSION := 2`、`MAX_BYTES := 2*1024*1024`、`MAX_PIECES := 300`、`MAX_OBSTACLES := 500`
  - `to_json(level_data, pretty)` = `JSON.stringify(data, "\t" or "", false)`（**第三参 sort_keys=false**）
- `scripts/ui/result_screen.gd`：`:57 _add_upload_button_if_eligible()`、`:67` 函数定义、
  `:76 upload.text = "上传到关卡广场"`、`:81 CommunityService.upload_level(...)`、
  `:84` "已提交审核" / "已上传到广场"、`:86` 失败文案 → **任务一要删除的入口**
- 自制关卡本地存储：`data/level_repository.gd` `USER_LEVEL_DIRECTORY := "user://levels"`、
  `:46` 扫描构造摘要列表；`autoload/level_catalog.gd:118 get_raw_level(level_id)`；
  编辑器保存点 `scripts/editor/level_editor.gd:1883`（"已保存到 user://levels/%s.json"）
- 平台判定 `scripts/autoload/platform_config.gd`：
  - `is_web = OS.has_feature("web")`
  - `is_wechat = OS.has_feature("wechat") or JavaScriptBridge.get_interface("wx") != null`（仅在 is_web 时判）
  - `get_platform_id()` → `"wechat"` / `"web"` / OS 名小写 / `"unknown"`
  - `is_mobile = OS.has_feature("mobile")`

### 服务端（Node.js，仓库内 `server/`）
- `server/src/app.js:277` `app.post("/api/ugc/upload", uploadRateLimit, async (req,res,next) => ...)`
  - `normalizeUploadEnvelope(req.body)`（来自 `ugc_validation.js`）
  - `ugcStore.countByAuthor(authorId) >= maxLevelsPerAuthor` → 429 `author_upload_limit`
  - `reviewMode === "pending"` ? mock pending : `await moderateUgcContent(normalized)`
  - `makeUgcId()` = `` `ugc_${Date.now().toString(36)}_${crypto.randomBytes(4).toString("hex")}` ``
  - `normalized.level.id = id` → `ugcStore.create({...})`
  - 响应 `res.status(review.status === "approved" ? 201 : 202).json({ok:true, id, review_status, review_provider, entry})`
  - `:155 uploadRateLimit = createRateLimiter({windowMs: 3_600_000, max: 30, keyPrefix: "upload"})`
  - `:159 app.use("/api/ugc/upload", express.json({limit: "3mb"}))`
  - `:15 UGC_ID_RE = /^[A-Za-z0-9_-]{1,80}$/`
- `server/src/ugc_store.js`：`create(entry)` INSERT INTO `ugc_levels`
  (`id,name,author_id,author_name,description,platform,difficulty,schema_version,`
  `level_bytes,level_json,review_status,review_provider,review_reason,created_at,updated_at`)，
  `levelJson = JSON.stringify(entry.level)`，`level_bytes = Buffer.byteLength(levelJson,"utf8")`；
  另有 `list/getSummary/getDetail/incrementPlays/toggleLike/toggleFavorite/delete/countByAuthor/toSummary`
- `server/src/db.js`：`:35 CREATE TABLE IF NOT EXISTS ugc_levels`；
  **`:100 ensureColumns(db, "ugc_levels", {...})` 已有列迁移机制**（`:13 ALTER TABLE ADD COLUMN`）；
  `:115-120` 三个索引（feed / hot / author）。`telemetry_events` 有 `event_id TEXT UNIQUE` 先例。
- 测试：`server/test/ugc_api.test.js`、`server/test/review_pending.test.js`

### 关键空白
- **项目内无任何抖音/tt/bytedance 相关代码**（仅 `dashboard/dist` 压缩产物误命中）。
- `export_presets.cfg` 三个 preset：`:8 custom_features=""`、`:76 custom_features="wechat"`、`:122 custom_features=""`
  → **只有微信特性标记，没有抖音**。

---

## 三、方案设计（待确认）

### 3.1 关卡内容指纹（Hash）

**指纹必须基于「规范化后的 level_data」，绝不能基于原始草稿 JSON。**
理由：编辑器草稿含 `id`、字段顺序、浮点尾数等易变量；而 `_normalize_level()` 已经把
数值 `snappedf(v,0.001)`、颜色小写化、枚举白名单裁剪、字段顺序固定，
是唯一能保证「同一关卡在不同设备/不同次导出算出同一指纹」的输入。

**必须排除的字段**：`id`（服务端上传时才分配）、`name`/`description`（改名不应产生新关卡）、
`source`/`custom`（派生标记）。指纹只覆盖**玩法内容**：
`schema_version, difficulty, par_time, countdown_seconds, time_limit_seconds, background_id, track, obstacles, theme, camera_bounds, analytics_tags`。

**算法**：SHA-256（不用 MD5，抗碰撞且各端原生可得）。
- 客户端：Godot 内置 `HashingContext` / `String.sha256_text()`，**零依赖、零包体增长**。
- 服务端：Node 内置 `crypto.createHash("sha256")`。
- 输入序列化：`JSON.stringify(obj, null, 0)` 但**必须键有序**。Godot 的
  `JSON.stringify(data, "", false)` 第三参是 sort_keys，**不能依赖它跨端一致**；
  方案是两端各自实现同一个「递归按键名排序 → 紧凑序列化」的规范化函数
  （服务端 `canonicalize()`，客户端 `_canonical_json()`），并约定：
  数字统一按 `snappedf(v,0.001)` 后去尾零输出、字符串原样、布尔小写、数组保序、对象按键名升序。
- **指纹由服务端复算，不信任客户端**：客户端可传 `content_hash` 作为快速路径，
  但服务端必须用同一算法对 `normalized.level` 复算并**以服务端结果为准**，
  否则抓包改 hash 即可绕过去重（任务三的核心诉求）。

**传递方式**：请求体新增顶层字段 `content_hash`（64 位小写十六进制字符串，服务端用
`/^[a-f0-9]{64}$/` 校验，非法则忽略客户端值、只用自己复算的结果）。

### 3.2 本地存档结构改动

`user://levels/<id>.json` 新增顶层字段：
```json
{
  "server_id": "ugc_xxx",        // 上传成功后写回；空字符串或不存在 = 未上传
  "server_content_hash": "abc…", // 服务端确认的指纹，用于校验本地内容是否又被改过
  "server_uploaded_at": 1731484800
}
```
- 用 `server_id` 而非 `is_uploaded` 布尔：单一真相来源，且天然支持「已在广场的哪一条」。
- 三个字段都在 `_normalize_level` 的**输出之外**（规范化字典不含它们），
  因此不影响指纹计算，也不影响 `LevelData.from_dictionary()`。
- **风险点（需实现时验证）**：编辑器保存会整体覆写该 JSON。
  必须在编辑器保存路径里**读出旧文件、保留这三个 server_* 字段再写回**，
  否则玩家改一次关卡就丢已上传状态、又能重复上传。
- 兼容：旧文件没有这些字段 → 视为未上传，不报错。

### 3.3 服务端幂等

`ugc_levels` 新增列（走已有 `ensureColumns` 迁移机制，无需手工 SQL）：
- `content_hash TEXT`
- `UNIQUE(author_id, content_hash)` 索引

**入库流程改为**：
1. `normalizeUploadEnvelope` → 服务端复算 `content_hash`
2. 查 `SELECT id, review_status FROM ugc_levels WHERE author_id=? AND content_hash=?`
3. 命中 → **不入库**，返回 `200 {ok:true, id:<已有id>, duplicate:true, review_status:<已有状态>, entry:<已有摘要>}`
4. 未命中 → 走原审核 + `create()` 流程，写入 `content_hash`
5. 并发兜底：INSERT 撞 UNIQUE 约束时 catch `SQLITE_CONSTRAINT`，回查已有 id 按 3 返回
   （这是「同一时间内只能上传一次」的真正保障，SELECT 检查本身有竞态）

**去重范围建议：`author_id + content_hash`，而非全局 hash。**
理由：全局去重下，恶意用户可抢先上传他人关卡内容「占用」指纹，把原作者永久挡在门外；
而任务三要防的是「同一用户恶意刷库」，作者维度已足够，且不误伤巧合撞车的不同作者。
（此项需用户确认，见 3.5 问题 2）

### 3.4 客户端状态锁与多端权限

- `CommunityService.upload_level()` 开头加：本地 JSON 已有 `server_id` → 直接回调
  `{ok:false, error:"该关卡已上传到广场"}`，**不发请求**。
- `result_screen.gd` 删除 `_add_upload_button_if_eligible()` 整个入口（`:57` 调用 + `:67` 函数）。
- 关卡广场「上传板块」与选关界面：`server_id` 非空 → 按钮显示「已上传」且 `disabled = true`。
- `PlatformConfig` 新增 `can_upload_ugc: bool` 与 `is_douyin: bool`，
  在 `_ready()` 里统一判定；UI 只读 `PlatformConfig.can_upload_ugc`，
  **不再散落 `if OS.has_feature("web")`**。
- Web 端（`is_web and not is_wechat and not is_douyin`）→ `can_upload_ugc = false`，
  隐藏上传按钮，保留广场只读与关卡工坊本地创作。
- PC / Android / 微信 → `can_upload_ugc = true`。

### 3.5 用户已确认的四项决策（2026-11-13）

1. **抖音判定 = 预留判定，本轮不验证**。按「自定义导出特性 `douyin` + 运行时探测
   `JavaScriptBridge.get_interface("tt") != null`」实现 `is_douyin`，计入 `can_upload_ugc` 白名单。
   因为没有抖音导出预设，本轮无法真机验证，等接入抖音导出时自然生效。
2. **去重范围 = `UNIQUE(author_id, content_hash)`**（作者维度，防指纹抢注）。
3. **撤销上传后 = 清空本地 `server_*` 标记，允许重新上传**（与现有 `upload_count -= 1` 一致）。
4. **itch.io（普通 Web）一并禁止上传**，不新增域名白名单或额外特性标记。

### 3.6 原始待确认问题（已由 3.5 回答，保留备查）

1. **抖音端如何判定？** 项目内零抖音代码，`export_presets.cfg` 也只有 `wechat` 特性。
   抖音小游戏是否已实际接入？若已接入，用哪种判定——
   `OS.has_feature("douyin")`（需先在导出预设加自定义特性）、
   还是运行时探测 `JavaScriptBridge.get_interface("tt") != null`？
   若尚未接入，本轮是否只按「预留 is_douyin 判定 + 特性标记」实现、暂不验证？
2. **去重范围**：`author_id + content_hash`（推荐，防抢占）还是全局 `content_hash`（更严，
   但存在恶意抢注他人关卡指纹的风险）？
3. **撤销上传后**：现有 `community_service.gd:454` 有 `upload_count -= 1` 的撤销逻辑。
   撤销后是否要清空本地 `server_id`、允许重新上传？还是保留已上传标记永久锁定？
4. **itch.io（Web）与「普通 Web」是否需要区分？** 两者都是 `OS.has_feature("web")` 且无小游戏特性，
   按现方案都会被禁上传。itch.io 是否也希望禁？（若希望 itch.io 可上传，需要额外的判定依据，
   例如导出特性标记或域名白名单——这属于新增机制，需你确认。）

---

## 四、待实施清单（确认后执行）

- [ ] 客户端：`UgcLevelDocument` 加 `_canonical_json()` + `compute_content_hash(level_data)`
- [ ] 客户端：`community_service.gd` 上传前查 `server_id`、上传成功回写三个 `server_*` 字段
- [ ] 客户端：`level_repository.gd` / `level_editor.gd` 保存时保留 `server_*` 字段
- [ ] 客户端：`platform_config.gd` 加 `is_douyin` / `can_upload_ugc`
- [ ] 客户端：`result_screen.gd` 删除上传入口；广场上传板块 + 选关界面加「已上传」禁用态
- [ ] 服务端：`db.js` 加 `content_hash` 列与 UNIQUE 索引
- [ ] 服务端：`ugc_store.js` 加 `findByAuthorHash()`、`create()` 写 hash、撞约束回查
- [ ] 服务端：`app.js` 上传接口加复算 + 幂等分支 + `duplicate:true` 响应
- [ ] 服务端：`ugc_validation.js` 的 `normalizeUploadEnvelope` 接收/校验 `content_hash`
- [ ] 测试：`server/test/ugc_api.test.js` 加重复上传用例；Godot `tests/test_runner.gd` 加本地锁用例
