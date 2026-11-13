# UGC 关卡广场 · 前后端联调文档

本文档对应 `server/`（Node.js + Express + SQLite）与 Godot 客户端
`ApiClient` / `CommunityService` / `UgcLevelDocument`。

当前联调地址：

```text
http://8.134.212.65:3000
```

本地联调可改为：

```text
http://127.0.0.1:3000
```

Godot 端只改一个全局变量：

```gdscript
# scripts/services/network/api_client.gd
@export var base_url: String = "http://8.134.212.65:3000"
```

域名备案完成后改成 `https://你的域名` 即可，业务代码不需要改。

> 微信正式版要求 HTTPS + 已备案域名，并在微信公众平台配置
> `request` / `downloadFile` 合法域名。IP + HTTP 只能用于开发者工具或
> 关闭域名校验的调试阶段。

---

## 1. 关卡 JSON 结构

关卡数据是跨 PC / Android / 微信的统一 JSON。服务端只接受白名单字段，
并对数字、数组长度、文本长度和总大小做校验。

### 1.1 顶层字段

```json
{
  "schema_version": 2,
  "id": "ugc_mw6cth0q_fb2e3416",
  "name": "云端小环线",
  "subtitle": "自制关卡",
  "description": "在关卡工坊中拼接的轨道。",
  "difficulty": 2,
  "par_time": 60,
  "countdown_seconds": 3,
  "time_limit_seconds": 180,
  "background_id": "forest",
  "custom": true,
  "source": "community",
  "track": { "start_angle_deg": 0, "pieces": [], "start_s": 60, "finish_s": 600 },
  "obstacles": [],
  "analytics_tags": ["自制"],
  "theme": {
    "sky_top": "#68cdf2",
    "sky_bottom": "#fff1b8",
    "mountain_far": "#80d8d2",
    "mountain_near": "#2ec4b6",
    "track": "#2f4b68",
    "track_highlight": "#b9d6e5",
    "accent": "#ff6b5b"
  },
  "camera_bounds": { "x": -120, "y": -120, "w": 1600, "h": 900 }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `schema_version` | int | 当前固定为 `2` |
| `id` | string | 上传时由服务端生成，客户端传入的 id 会被丢弃 |
| `name` | string | 关卡名，1–48 字符 |
| `subtitle` | string | 副标题，最多 72 字符 |
| `description` | string | 简介，最多 500 字符 |
| `difficulty` | int | 1–5 |
| `par_time` | number | 1–3600 秒 |
| `countdown_seconds` | number | 0.5–10 秒 |
| `time_limit_seconds` | number | 0–86400 秒，0 表示无限 |
| `background_id` | string | `paradise` / `forest` / `snow` / `clouds` / `dream` |
| `custom` | bool | 服务端强制 `true` |
| `source` | string | 服务端强制 `community` |
| `track` | object | 见 1.2 |
| `obstacles` | array | 见 1.3，最多 500 个 |
| `analytics_tags` | array | 最多 16 个，每个最多 32 字符 |
| `theme` | object | 可选；颜色必须是 `#RRGGBB` |
| `camera_bounds` | object | 可选；`x/y/w/h`，`w/h >= 64` |

### 1.2 轨道 track

```json
{
  "start_angle_deg": 0,
  "pieces": [
    { "type": "straight", "length": 240, "direction": 1, "direction_anchor": true },
    { "type": "arc", "radius": 120, "angle": -45, "direction": 1 },
    { "type": "loop", "radius": 90, "angle": -360, "direction": 1 }
  ],
  "start_s": 60,
  "finish_s": 600
}
```

- 最多 300 个片段；总长度 400–120000 px。
- `type`：`straight` / `arc` / `loop`（旧数据里的 `curve` 会归一为 `arc`）。
- `straight`：`length`；`arc`/`loop`：`radius` + `angle`。
- 可选 `origin: [x, y]` 与 `heading_deg` 表示自由放置形成的断口。
- `direction`：`1` 或 `-1`；`direction_anchor` 表示该段首片段。
- `break_after`：定时断开秒数，0–60；0 表示不断开。
- `start_s` / `finish_s` 必须落在轨道弧长范围内，且相距至少 100 px。

### 1.3 障碍 obstacles

编辑器当前写入的核心字段：

```json
{
  "prefab": "bird",
  "s": 1200,
  "offset": { "x": 0, "y": -60 },
  "flip_x": false
}
```

> `offset`、`motion.amplitude`、`collision_offsets[]` 必须是 `{x,y}` 对象。
> 不要用 `[x,y]` 数组：`LevelData` 的障碍清洗逻辑只接受 Dictionary / Vector2，
> 数组会被当成 `Vector2.ZERO`，导致下载后障碍丢失偏移。
> 服务端兼容旧数据中的数组，但新上传统一输出对象。

服务端还兼容以下可选字段（都有范围限制）：

- `motion`：`{ type, amplitude, speed, phase }`，类型 `static` / `oscillate_x` /
  `oscillate_y` / `circle` / `ellipse`；
- `radius`、`damage`；
- `collision_offsets`、`collision_radii`（最多 8 组）；
- `interval_enabled` / `interval_period` / `interval_active`；
- `trigger_enabled`、`clockwise`。

`prefab` 必须是游戏内 20 个障碍之一。未知字段会被丢弃，不会原样入库。

### 1.4 大小与安全限制

| 限制 | 值 |
|---|---|
| 关卡正文 JSON | ≤ 2 MB |
| 请求体（含信封） | ≤ 3 MB（Express 层） |
| 轨道片段 | ≤ 300 |
| 障碍 | ≤ 500 |
| 文本字段 | 见上表，服务端会去除控制字符 |
| 数字 | 必须是有限数，禁止 NaN / Infinity |

服务端不会信任客户端的 `id`、`custom`、`source`、`author_id` 等身份字段；
`id` 由服务端生成，`author_id` 只用于归属与撤销校验。

---

## 2. 上传与试玩流程

```text
工坊保存 -> user://levels/custom_*.json
        -> 玩家亲自通关
        -> 关卡广场「上传关卡」
        -> POST /api/ugc/upload
        -> 服务端校验 + 审核(mock/真实 msgSecCheck)
        -> SQLite ugc_levels
        -> GET /api/ugc/list（摘要）
        -> 点击试玩
        -> GET /api/ugc/detail/:id（完整关卡）
        -> UgcLevelDocument 客户端二次校验
        -> POST /api/ugc/:id/play 计数
        -> GameSession.start_community_level
```

客户端上传前会：

1. 读取 `LevelCatalog` 的原始 JSON；
2. 用 `UgcLevelDocument` 归一化所有编辑器字段；
3. 用 `LevelData` 做一次玩法校验；
4. 检查 2MB 上限；
5. 发送 `{name, author_name, author_id, platform, description, level_data}`。

---

## 3. API

统一响应包含 `ok`。失败时：

```json
{ "ok": false, "error": "invalid_level", "detail": "track.pieces 至少需要一个片段" }
```

客户端优先展示 `detail`（中文），没有时按 `error` / HTTP 状态码映射。

### 3.1 `GET /health`

存活检查。

```json
{
  "ok": true,
  "service": "cablecar-server",
  "database": "sqlite",
  "ugc_review_mode": "mock",
  "time": "2026-11-07T12:00:00.000Z"
}
```

### 3.2 `POST /api/ugc/upload`

上传关卡。`Content-Type: application/json`。

请求体：

```json
{
  "name": "云端小环线",
  "author_name": "游客",
  "author_id": "local_player",
  "platform": "windows",
  "description": "自制关卡",
  "level_data": { "...": "完整关卡 JSON" }
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 是 | 广场显示名，1–48 字符 |
| `author_name` | 是 | 作者昵称，1–24 字符 |
| `author_id` | 是 | 客户端稳定 id，`[A-Za-z0-9_.-]{1,64}`；Godot 端使用 `SaveManager.get_player_id()`（`SW-xxxxxx`），不再使用所有人共用的 `local_player` |
| `platform` | 否 | `windows` / `android` / `ios` / `web` / `wechat` / `linux` / `macos` / `unknown` |
| `description` | 否 | 最多 200 字符 |
| `level_data` | 是 | 完整关卡对象，≤ 2MB |

成功 `201`（`UGC_REVIEW_MODE=mock`）：

```json
{
  "ok": true,
  "id": "ugc_mw6cth0q_fb2e3416",
  "review_status": "approved",
  "review_provider": "mock",
  "entry": {
    "id": "ugc_mw6cth0q_fb2e3416",
    "name": "云端小环线",
    "author": "游客",
    "author_id": "local_player",
    "description": "自制关卡",
    "platform": "windows",
    "difficulty": 2,
    "plays": 0,
    "likes": 0,
    "favorites": 0,
    "clears": 0,
    "created_at": "2026-11-07T12:00:00.000Z",
    "liked": false,
    "favorited": false
  }
}
```

审核待定模式返回 `202` 且 `review_status: "pending"`，此时不会出现在列表。

常见错误：

| HTTP | error | 说明 |
|---|---|---|
| 400 | `invalid_level` / `invalid_track` | 关卡结构错误 |
| 400 | `invalid_obstacle` | 障碍 prefab 或 s 非法 |
| 400 | `text_too_long` | 名称/简介超长 |
| 413 | `payload_too_large` | 关卡正文 > 2MB 或请求体过大 |
| 429 | `rate_limited` | 上传频率过高（30 次/小时/IP） |
| 429 | `author_upload_limit` | 单作者关卡数超限（默认 3） |

### 3.3 `GET /api/ugc/list`

广场列表，只返回摘要，不返回 `level_data`。

查询参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `page` | `1` | 页码，1–10000 |
| `page_size` | `20` | 每页 1–50 |
| `sort` | `latest` | `latest` / `hot` / `oldest` |
| `author_id` | 空 | 只看某作者（“我的”） |
| `platform` | 空 | 按来源平台过滤 |
| `q` | 空 | 名称搜索，最多 32 字符 |
| `player_id` | 空 | 传入后返回 `liked` / `favorited` |

响应：

```json
{
  "ok": true,
  "page": 1,
  "page_size": 20,
  "total": 1,
  "hasMore": false,
  "entries": [
    {
      "id": "ugc_mw6cth0q_fb2e3416",
      "name": "云端小环线",
      "author": "游客",
      "author_id": "local_player",
      "description": "自制关卡",
      "platform": "windows",
      "difficulty": 2,
      "plays": 12,
      "likes": 3,
      "favorites": 1,
      "clears": 0,
      "created_at": "2026-11-07T12:00:00.000Z",
      "liked": false,
      "favorited": false
    }
  ]
}
```

### 3.4 `GET /api/ugc/detail/:id`

返回完整关卡，供客户端下载后试玩。

查询参数：`player_id` 可选，用于返回点赞/收藏状态。

响应：

```json
{
  "ok": true,
  "entry": {
    "id": "ugc_mw6cth0q_fb2e3416",
    "name": "云端小环线",
    "author": "游客",
    "author_id": "local_player",
    "description": "自制关卡",
    "platform": "windows",
    "difficulty": 2,
    "plays": 12,
    "likes": 3,
    "favorites": 1,
    "clears": 0,
    "created_at": "2026-11-07T12:00:00.000Z",
    "level_bytes": 19234,
    "level_data": { "...": "完整关卡 JSON" }
  }
}
```

`404 not_found`：不存在、未审核通过或已删除。

### 3.5 `POST /api/ugc/:id/play`

游玩计数 +1。

```json
{ "ok": true, "plays": 13 }
```

### 3.6 `POST /api/ugc/:id/like`

点赞 / 取消点赞（同一 `player_id` 幂等切换）。

```json
{ "player_id": "local_player" }
```

```json
{ "ok": true, "liked": true, "likes": 4 }
```

### 3.7 `POST /api/ugc/:id/favorite`

收藏 / 取消收藏。

```json
{ "player_id": "local_player" }
```

```json
{ "ok": true, "favorited": true, "favorites": 2 }
```

### 3.8 `DELETE /api/ugc/:id`

撤销自己的上传。

```json
{ "author_id": "local_player" }
```

也支持 `X-Player-Id` 请求头。只有 `author_id` 与原记录一致才允许删除。

```json
{ "ok": true }
```

### 3.9 `POST /api/telemetry`

客户端关键行为上报。客户端在以下时机发送：

- `enter_custom_level`：进入自制 / 广场关卡；
- `run_end`：通关或死亡结算；
- `collision`：碰撞障碍（稀疏事件，用于卡点热力图与障碍类型分析）。

`run_end` / `collision` 的 `payload` 会附带 `player_id` 与 `session_id`（由
`RemoteTelemetryReporter` 注入）。服务端只用于去重统计，看板接口不会返回明细。

请求体：

```json
{
  "event_id": "s_123_456_789",
  "event_type": "run_end",
  "platform": "android",
  "level_id": "ugc_mw6cth0q_fb2e3416",
  "level_name": "云端小环线",
  "mode": "solo",
  "custom": true,
  "ts": 1762516800.123,
  "payload": {
    "completed": true,
    "passengers": 3,
    "time_seconds": 42.5,
    "lost_passengers": 0
  }
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `event_type` | 是 | `run_end` / `enter_custom_level` / `collision` |
| `platform` | 是 | 同上平台枚举 |
| `event_id` | 否 | 用于去重；重复上报返回 `duplicate: true` |
| `level_id` / `level_name` / `mode` | 否 | 关卡与模式 |
| `custom` | 否 | 是否自制关卡 |
| `ts` | 否 | 客户端 Unix 时间戳 |
| `payload` | 否 | 原始事件字段，≤ 32KB |

响应 `202`：

```json
{ "ok": true, "duplicate": false, "event_id": "s_123_456_789" }
```

### 3.10 `GET /api/telemetry/summary`

看板数据源，按天/事件/平台聚合，只返回统计值，不返回玩家明细。

查询参数：`days` 默认 7，1–90。

```json
{
  "ok": true,
  "days": 7,
  "since": "2026-10-31T12:00:00.000Z",
  "by_day": [
    { "day": "2026-11-07", "event_type": "run_end", "platform": "android", "count": 30 }
  ],
  "totals": [
    { "event_type": "run_end", "count": 120 }
  ]
}
```

### 3.11 `GET /api/telemetry/dashboard`

Vue 3 + ECharts 看板的一次性聚合接口。查询参数 `days` 默认 7，范围 1–90。
只返回聚合值，不返回 `player_id` / `session_id` 明细。

返回结构：

```json
{
  "ok": true,
  "days": 7,
  "generated_at": "2026-11-08T08:00:00.000Z",
  "range": { "from": "2026-11-01T08:00:00.000Z", "to": "2026-11-08T08:00:00.000Z" },
  "kpis": {
    "runs": 262,
    "completed": 135,
    "completion_rate": 51.53,
    "unique_players": 48,
    "collisions": 349,
    "collisions_per_run": 1.33,
    "avg_time": 58.32,
    "ugc_runs": 64
  },
  "deltas": { "runs": 12.4, "completion_rate": -1.8 },
  "trend": [
    { "date": "2026-11-08", "runs": 38, "completed": 20, "failures": 18, "completion_rate": 52.6, "collisions": 46, "players": 31 }
  ],
  "platforms": [
    { "id": "wechat", "runs": 99, "completed": 52, "completion_rate": 52.53, "avg_time": 86.54, "share": 37.79 }
  ],
  "main_levels": [
    { "level_id": "level_01", "name": "晴空初旅", "runs": 40, "completed": 35, "completion_rate": 87.5 }
  ],
  "collisions": {
    "by_type": [{ "id": "bird", "count": 84 }],
    "progress_bins": [
      { "index": 0, "label": "0-5%", "collisions": 2, "failures": 1 }
    ]
  },
  "choke_levels": [
    { "level_id": "ugc_x", "name": "三连死亡环", "custom": true, "failed": 21, "collisions": 46, "score": 88 }
  ],
  "ugc": {
    "funnel": { "enters": 88, "runs": 64, "completed": 27, "churn_rate": 69.32 },
    "levels": [
      { "level_id": "ugc_x", "name": "三连死亡环", "plays": 2100, "heat_score": 100, "churn_rate": 87.5 }
    ]
  },
  "recent_runs": [
    { "level_name": "晴空初旅", "platform": "wechat", "completed": true, "stars": 3, "time_seconds": 42.1 }
  ],
  "passengers": { "saved": 337, "lost": 442, "saved_ratio": 43.26 }
}
```

口径：

- `unique_players`：`run_end` / `enter_custom_level` / `collision` 的 `player_id` 去重，缺省回退 `session_id`；
- `choke_levels` 分数：`failed × 2 + collisions`；
- UGC 劝退率：`(max(enters, runs) - completed) / max(enters, runs)`；
- UGC 热度：`ln(1+plays)*0.34 + ln(1+max(enters,runs))*0.30 + ln(1+likes)*0.22 + ln(1+favorites)*0.14`，归一化到 0–100。

### 3.12 保留的微信接口

- `POST /api/login`：微信 `code` 换 `openid`，签发 7 天会话令牌；
- `POST /api/ugc/check`：调用微信 `msgSecCheck` 审核单段文本；
- `GET /game/*`：远程 `wasm` / `pck` / Brotli 资源。

---

## 4. 审核流转与微信合规

当前 `UGC_REVIEW_MODE=mock`：

```text
上传 -> moderateUgcContent() -> approved
```

代码位置：`server/src/app.js` 的 `moderateUgcContent()`。

正式接入微信时的 TODO：

1. 微信端登录后拿到 `openid`；
2. 对 `name`、`description`、`author_name` 分别调用
   `wxa/msg_sec_check`（`/api/ugc/check` 已封装单段文本审核）；
3. 审核通过写 `review_status = "approved"`；
4. 命中风险或需人工复核写 `review_status = "pending"` / `"rejected"`；
5. `GET /api/ugc/list` 只返回 `approved`。

也可以把 `UGC_REVIEW_MODE` 设为 `pending` 做完整“先审后发”联调：
上传返回 `202`，广场列表暂时看不到该关卡。

当前 PC / Android 端没有账号体系，`author_id` 只用于归属和撤销校验，不能作为
强身份凭证。正式上线微信端时建议把上传/撤销接口绑定 `/api/login` 下发的
`Authorization: Bearer <token>`，从 token 中取 `openid` 作为作者身份，而不是
信任客户端传入的 `author_id`。

---

## 5. 后端存储

SQLite 默认路径：

```text
server/data/cablecar.sqlite
```

可用环境变量覆盖：

```text
UGC_DB_PATH=/opt/cablecar-server/data/cablecar.sqlite
```

表结构：

- `ugc_levels`：摘要列 + 完整 `level_json`；
- `ugc_likes` / `ugc_favorites`：按 `(entry_id, player_id)` 唯一；
- `telemetry_events`：原始 payload JSON，`event_id` 唯一去重。

备份：直接备份 `data/cablecar.sqlite` 及 `-wal` / `-shm` 文件，或使用
`sqlite3 data/cablecar.sqlite ".backup backup.sqlite"`。

---

## 6. 部署 / 本地启动

```powershell
cd server
npm install
Copy-Item .env.example .env
# 编辑 .env：WECHAT_APP_SECRET / SESSION_SECRET / UGC_DB_PATH
npm start
```

服务器：

```bash
cd /opt/cablecar-server
npm ci --omit=dev
mkdir -p data public/game
pm2 restart ecosystem.config.cjs
```

Nginx 已把 `client_max_body_size` 调到 `4m`，后端内部仍按 2MB 精确拦截。
`/api/` 反向代理到 `127.0.0.1:3000`。

---

## 7. 自动化测试

后端接口：

```powershell
cd server
npm test
```

Godot 联调冒烟测试（需要先启动后端 `127.0.0.1:3100`）：

```powershell
cd server
$env:PORT="3100"; $env:UGC_DB_PATH="./data/live-smoke.sqlite"; npm start
```

另开终端：

```powershell
& "D:\Tools\GameTools\GODOT\Godot_v4.5.1-stable_win64_console.exe" `
  --headless --path "D:\Tools\GameTools\GODOT\GodotGames\skywire-remake" `
  res://tests/live_ugc_smoke.tscn
```

可用 `UGC_SMOKE_LEVEL=level_11` 指定用哪张内置关卡生成联调关卡。

Godot 常规回归：

```powershell
.\tools\run_tests.ps1
```

---

## 8. PowerShell 联调示例

```powershell
$base = "http://8.134.212.65:3000"
Invoke-RestMethod "$base/health"

$level = Get-Content ".\data\levels\level_01.json" -Raw | ConvertFrom-Json
$body = @{
  name = "联调关卡"
  author_name = "游客"
  author_id = "local_player"
  platform = "windows"
  description = "联调"
  level_data = $level
} | ConvertTo-Json -Depth 20

$uploaded = Invoke-RestMethod "$base/api/ugc/upload" `
  -Method Post -ContentType "application/json" `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
$uploaded.id
Invoke-RestMethod "$base/api/ugc/list?page=1&page_size=10"
```

> 注意：PowerShell 5 的 `ConvertTo-Json` 对中文编码敏感，建议用 Node 或
> `Invoke-RestMethod` 配合 UTF-8 字节数组；本项目后端测试使用 Node 编写。
