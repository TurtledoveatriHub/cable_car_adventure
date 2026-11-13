# 微信小游戏 / UGC 关卡广场后端

Node.js 20 + Express 5 + SQLite（`better-sqlite3`）。提供：

- `GET /health`：存活检查
- `POST /api/login`：微信 `code` 换 `openid`，签发 7 天会话令牌
- `POST /api/ugc/check`：调用微信 `msgSecCheck` 审核 UGC 文本
- `POST /api/ugc/upload`：上传关卡（2MB 上限、白名单校验、审核占位）
- `GET /api/ugc/list`：广场分页摘要，不返回完整关卡
- `GET /api/ugc/detail/:id`：完整关卡下载
- `POST /api/ugc/:id/play`：游玩计数
- `POST /api/ugc/:id/like` / `favorite`：点赞、收藏
- `DELETE /api/ugc/:id`：作者撤销上传
- `POST /api/telemetry`：关键行为遥测入库
- `GET /api/telemetry/summary`：按天/事件/平台聚合
- `GET /api/telemetry/dashboard`：Vue + ECharts 看板一次性聚合（KPI / 趋势 / 三端 / 主线 / 卡点 / UGC）
- `GET /game/*`：远程 wasm / pck / 资源下载

完整接口、JSON 结构、审核流转和联调示例见
[`docs/UGC_API.md`](../docs/UGC_API.md)。

## 本地测试

```powershell
cd server
npm install
Copy-Item .env.example .env
# 编辑 .env，填 WECHAT_APP_SECRET 和 SESSION_SECRET
npm start
```

```powershell
curl http://127.0.0.1:3000/health

# 后端自动化测试（内存 SQLite，不依赖微信）
npm test
```

## 数据看板

Vue 3 看板位于 [`../dashboard`](../dashboard/README.md)。开发联调：

```powershell
cd dashboard
npm install
npm run dev
```

Vite 默认把 `/api` 代理到 `http://127.0.0.1:3000`。如需一份独立演示数据：

```powershell
cd server
$env:UGC_DB_PATH="$PWD\data\dashboard_demo.sqlite"
npm run seed:demo
$env:PORT="3100"; node src/server.js
```

随后在 `dashboard` 中设置 `$env:VITE_API_PROXY="http://127.0.0.1:3100"` 再启动 Vite。
`seed_demo.js` 只允许写入文件名包含 `demo` 的数据库，不会碰正式库。

CORS 已通过 `cors` 中间件在 `src/app.js` 中统一处理；生产环境可用 `ALLOWED_ORIGIN` 限定域名。

看板聚合对历史脏数据做了两层保护：所有 `json_extract` 查询都带 `json_valid(payload_json)`，
且 `TelemetryStore.dashboard()` 捕获异常后返回同构全零 JSON（不会 500）。空库、损坏 JSON、
旧库缺列都能返回 200；具体错误写入 Node 日志 `pm2 logs cablecar`。

默认数据库：

```text
server/data/cablecar.sqlite
```

可用 `.env` 的 `UGC_DB_PATH` 覆盖。数据库文件、WAL 与 `node_modules` 不提交。

## 服务器部署（阿里云 Ubuntu 22.04）

```bash
# 本机
scp -r server root@8.134.212.65:/opt/cablecar-server

# 服务器
cd /opt/cablecar-server
npm ci --omit=dev
cp .env.example .env
nano .env
mkdir -p data public/game
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup
```

Nginx：

```bash
sudo cp nginx.conf.example /etc/nginx/sites-available/cablecar
sudo ln -s /etc/nginx/sites-available/cablecar /etc/nginx/sites-enabled/cablecar
sudo nginx -t
sudo systemctl reload nginx
```

IP 测试：

```text
http://8.134.212.65/health
http://8.134.212.65/api/ugc/list
http://8.134.212.65/api/login
http://8.134.212.65/game/...
```

## AppSecret

- 仅打包小游戏、导出客户端不需要 AppSecret；
- `jscode2session` 和 `msgSecCheck` 必须使用 AppID + AppSecret；
- 在微信公众平台「开发管理 → 开发设置 → AppSecret」生成；
- 只放在服务器 `.env`，不要写进 Godot 客户端、仓库、小程序前端；
- 重置 AppSecret 会使旧密钥立即失效，需要同步更新服务器；
- 未配置时 `/api/login` 返回 `503 server_appsecret_missing`，UGC mock 审核仍可联调。

## 无备案域名阶段

微信开发者工具可在「详情 → 本地设置」勾选“不校验合法域名、web-view（业务域名）、TLS 版本以及 HTTPS 证书”，用 IP 调试。

真机/正式版要求 `wx.request` 和资源下载走 **HTTPS 且已备案域名**，并加入微信后台的 request/downloadFile 合法域名。IP + HTTP 只能用于开发测试，不能作为正式小游戏域名。

## 远程资源

远程 wasm/pck 放到：

```text
/opt/cablecar-server/public/game/
```

Nginx 通过 `/game/` 暴露。`.br` 文件必须返回：

```text
Content-Encoding: br
Content-Type: application/octet-stream
```

否则浏览器/小游戏不会按 Brotli 解压。
