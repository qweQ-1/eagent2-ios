# EAgent iOS

0 tokens、0 门槛、轻量级 —— 移植自 [YaoGaoChaoLe/EAgent](https://github.com/YaoGaoChaoLe/EAgent)（Windows/易语言版）的 iPhone 版。

原版原理：Edge + CDP 自动化操控 DeepSeek 网页版，让 DeepSeek 生成 PowerShell 来"操控"你的电脑。
本版原理：App 内嵌 WKWebView 加载 DeepSeek 网页版（自己登录，0 token），通过 JS 注入实现「代发消息 / 轮询回复完成 / 读取回复文本」，模型按约定输出 `eagent` 工具块，原生执行 iPhone 能力（打开 App/网页、剪贴板、文件、TTS、提醒、日历、天气、定位、HTTP 请求、快捷指令、通知等），结果回灌给模型，循环成 Agent。

与 PC 版的对应关系：

| PC 版（易语言） | iOS 版 |
| --- | --- |
| 选择工作目录 | App 沙盒内 `Documents/workspace`，通过「文件」App 可直接访问 |
| Edge + CDP | WKWebView + 注入 JS（输入/发送/停止/取回复） |
| PowerShell 执行 | 原生工具集（见设置里的工具目录） |
| 窗口_安全警告（3~20 秒倒计时自动执行） | 安全门：逐条审批 / 自动模式 |
| 窗口_展示鼠标位置（动作可视化） | 悬浮动作条 + 记录页 |

## 使用

1. AltStore / Sideloadly 自签安装（仓库 Actions 产出未签名 IPA）。
2. 打开 App → 对话页：确认顶部显示「已登录」（在网页里扫码/账号登录 DeepSeek）。
3. 底部输入任务（例如「帮我建一个明天上午 9 点的提醒：开会」），点「发送任务」。
4. 模型回复里的工具调用会先弹安全门（可切自动模式），执行后自动回灌结果，直至模型给出最终答复。

## 声明

- 本项目基于 DeepSeek 网页版自动化，与反代一样违反 DeepSeek 用户协议，极端高频使用可能被风控，仅供学习交流，风险自负。
- 工具默认保守：文件仅限工作区、HTTP 禁止访问内网地址、外部链接需用户点击发送后才打开。

## 开发

- 工程由 XcodeGen 生成（`project.yml`），CI 见 `.ios-ci.yml` 与 `.github/workflows/`。
- 测试：`EAgent2Tests`（协议解析、提示词、日期解析、路径安全、安全门策略等纯逻辑）。
- 本地无 Mac，编译/测试全部走 GitHub Actions。
