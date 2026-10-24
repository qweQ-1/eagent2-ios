# AGENTS.md

本仓库是 EAgent iOS 移植版。规则：

- 编译与测试只在 GitHub Actions 上跑（见 `.ios-ci.yml`、`.github/workflows/`），本地无 Mac。
- 新功能必须带 `EAgent2Tests` 逻辑测试（解析、提示词、路径安全、日期等纯逻辑）。
- 只用原生能力，不引第三方依赖；新增权限要同步 `project.yml` 的 Info.plist 属性与 README。
- 部署只走 git push → CI；IPA 由 Unsigned IPA 工作流自动产出。
