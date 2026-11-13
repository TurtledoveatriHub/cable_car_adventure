# 第三方声明

## 字体

- **CableCarSans-Subset.otf**（`assets/fonts/CableCarSans-Subset.otf`）
  - 基于 **Noto Sans SC / Source Han Sans** 子集化生成；
  - 版权：Copyright 2014–2025 Adobe，Reserved Font Name 'Source'；
  - 授权：**SIL Open Font License 1.1**；
  - 许可证全文：[`assets/fonts/OFL.txt`](assets/fonts/OFL.txt)。

字体仅用于游戏 UI 文本渲染。再分发或继续子集化时，请保留本声明与许可证文件。

## 引擎

- **Godot Engine 4.5.1**，MIT License；
- 项目使用 GL Compatibility 渲染器。

## 服务端与看板依赖

- Node.js、Express、better-sqlite3、Vue 3、Vite、ECharts、Axios 等依赖遵循各自的开源许可证；
- 依赖清单见 `server/package.json`、`dashboard/package.json` 及对应 `package-lock.json`；
- `node_modules/` 不提交到仓库，部署时通过 `npm install` 还原。

## 游戏灵感

- 玩法参考 Nitrome 的 *Skywire*（中文常见译名《乐园过山车》）；
- 本项目不包含、不复用原作的图片、音频、关卡数据或代码；
- 轨道、角色、背景、UI、彩纸和程序化音效均来自本仓库的 Godot 绘制 / 合成代码；
- “Skywire Remake”等文字仅用于说明灵感来源，不代表与 Nitrome 存在官方关联。
