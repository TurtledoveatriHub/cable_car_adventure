# 微信小游戏导入说明

## 当前状态

已生成可直接导入微信开发者工具的小游戏目录：

```text
build/wechat/
```

界面选择 **小游戏**，导入 `build/wechat/`，不是 `build/web/`，也不是项目根目录。

已配置：

- 微信 AppID：`wx02e59af7baf92fcf`
- 横屏：`game.json` 的 `deviceOrientation = landscape`
- 主包：启动脚本、加载器、适配层
- 分包 `engine/`：
  - `godot.wasm.br` 6,240,533 字节
  - `game-pck.bin` 6,157,396 字节
  - `godot.js` 349,351 字节
- engine 分包约 12.80MB（12,801,322 字节）
- 压缩包：`build/standalone/CableCarAdventure-WeChat.zip`（10,906,619 字节）

引擎和 PCK 都放在 `engine` 分包内，不依赖远程 CDN；当前包体不需要域名即可加载游戏本体。

关卡内性能档（`PlatformConfig` 微信分支）：

- 帧率上限 60，DPR 上限 1.5（`game.js`）；
- 背景 30Hz、HUD 12Hz、粒子 40%；
- 关闭全屏 `BackBufferCopy + Shader` 后处理，改为单矩形雾化；
- 障碍视觉 30Hz、持续接触检测 20Hz；仅当障碍与缆车的空间距离超过 1200px 时停止障碍脚本/物理轮询（热气球、陨石常驻，避免长轨迹冻结）；
- 主线进度改用 `wx.setStorageSync` 持久化，结算时立即写入；旧 `user://` 存档首次启动自动迁移，避免 WXMEMFS 的 rename/目录同步导致重启丢档；
- 本地遥测在结算/退出时批量落盘，碰撞帧内不做文件 I/O；碰撞上报走串行队列；
- 关卡结束进入黑屏过渡，右下角显示“缆车进站中”，存档与遥测每帧最多 24 行分批写入；
- 中文字体改为 2.23MB 子集（GB2312 + 项目字符），原始 10.6MB 字体不再打包。

首次加载慢不是“测试版”独有：`engine` 分包下载/解包、WebAssembly 编译和 PCK 读入都是真实成本。
微信开发者工具首次编译尤其慢；真机、二次启动通常明显更快。旧的分包和字体会放大这一过程，
现已把分包降到约 12.80MB、字体降到 2.23MB。

加载流程：

1. 主包显示“首次加载需编译引擎”，分包进度实时显示；
2. engine 分包加载完成后，wasm 编译完成后再读取 PCK，避免真机文件系统回调与编译互相阻塞；
3. 不弹 `wx.showLoading` 原生遮罩（部分真机会暂停 WebView 渲染）；按模板顺序在 `engine.start` 前释放加载页 GL 资源；
4. 加载页清理后由 Godot 接管 canvas，避免加载页与引擎首帧争抢；
5. 加载页每 0.5 秒更新耗时秒数，失败时显示错误文本。

## 模板来源

使用 GodotHub `godot-minigame` 的 **4.5.1** 模板：

- 仓库：https://github.com/godothub/godot-minigame
- Tag：`4.5.1`
- 模板资产：`minigame4.5.1.3.tpz`
- 模板自带 4.5.1 微信小游戏运行时和 6.24MB wasm

注意：仓库 `main` 分支的 `skills/SKILL.md` 锁定 Godot 4.6.2-rc，不能直接用于 4.5.1。4.5.1 的模板已经包含可用运行时，因此本次直接使用 4.5.1 模板组装，而不是套用 main 分支 Skill。

## 手动步骤

1. 打开微信开发者工具，选择“小游戏”。
2. 导入目录：`build/wechat/`。
3. AppID 已写入 `project.config.json`，确认是 `wx02e59af7baf92fcf`。
4. 编译后先看控制台：
   - wasm 是否加载成功；
   - PCK 是否加载成功；
   - 是否有 `wx.createCanvas`、音频、文件系统的报错。
5. 真机预览，确认横屏、触摸、存档。

模板 README 提示：微信开发者工具需要开启：

```text
设置 → 通用设置 → 打开浏览器实验性设置
→ Experimental WebAssembly (Enabled)
```

然后重启开发者工具。

## 服务器与域名

游戏本体已在分包内，服务器主要用于：

- `wx.login` 换 openid；
- UGC 文本 `msgSecCheck`；
- UGC 关卡广场：上传 / 列表 / 详情 / 游玩计数 / 点赞收藏；
- 行为遥测 `/api/telemetry`；
- 以后资源热更新 / 排行榜。

客户端唯一需要改的后端地址在：

```text
scripts/services/network/api_client.gd -> base_url
```

接口、JSON 结构和审核流转见 [UGC_API.md](UGC_API.md)。

服务器代码在：

```text
server/
```

没有备案域名时：

- `http://8.134.212.65:3000/health` 可用于本机/浏览器测试；
- 微信开发者工具可勾选“不校验合法域名”用 IP 调试；
- **真机正式版必须使用 HTTPS + 已备案域名**，并加入微信后台 request 合法域名；
- IP + HTTP 不能作为正式小游戏请求域名。

## 包体判定

当前使用 4.5.1 专用裁剪运行时：

| 文件 | 大小 |
|---|---:|
| `godot.wasm.br` | 6,240,533 |
| `game-pck.bin` | 6,157,396 |
| `godot.js` | 349,351 |
| 其它启动文件 | 约 0.15MB |
| 合计 | 12,801,322（约 12.80MB） |

没有使用标准 Web 导出的 38MB wasm，因此不需要再做引擎裁剪，也不需要远程 wasm。

## AppSecret

- 导出/导入小游戏本体不需要 AppSecret；
- 服务器 `jscode2session`、`msgSecCheck` 需要 AppID + AppSecret；
- 在微信公众平台生成 AppSecret，只放服务器 `.env`；
- 不要把 AppSecret 写进 Godot 或 `game.js`。

## PCK 加载修复

模板默认通过浏览器 fetch/XHR 预加载 /engine/game.pck，在微信小游戏里会失败。

现在 `build/wechat/engine/game.js` 改为：

1. 初始化 Godot Engine；
2. 用 wx.getFileSystemManager().readFileSync('/engine/game.pck') 直接读取分包 PCK；
3. engine.preloadFile(new Uint8Array(file), pack)；
4. engine.start({ args: ['--main-pack', pack] })。

不再依赖 MiniGameAdapter 的 fetch 重写，也不需要把 PCK 嵌入 wasm。
