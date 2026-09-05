# BarCmd

macOS 菜单栏命令运行器。用菜单栏管理长期运行的 shell 命令，替代「挂一个终端」。

## 文档优先级

1. `docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md` — 产品规格（做什么）
2. `docs/superpowers/specs/2026-09-01-barcmd-architecture.md` — 架构（怎么做）
3. `ROADMAP.md` — 当前阶段和进度
4. `README.md` — 介绍和使用

规格与架构冲突时，先改规格再改架构，再改代码。不要只在代码里「变通」。

## 范围

只做规格里的 MVP。禁止顺手加：登录自启、autoStart、日志搜索、分组、多实例、设置页、Dock 图标、App Sandbox、iCloud。

## 工程约定

- 语言：Swift 5.9+，UI 用 SwiftUI，最低 macOS 14
- 第三方依赖只允许 Yams
- 标识符、文件名、命令用英文；用户可见文案用中文
- 进程、日志、配置、端口检测必须可单测或可集成测；改完跑相关测试
- 密钥不进仓库。本项目不应出现 token / `.env` 业务密钥
- 非沙盒 App；不要打开 App Sandbox
- Agent App：`LSUIElement`，无 Dock 图标

## Git

- 默认分支 `main`
- 提交前缀：`init:` / `feat:` / `fix:` / `refactor:` / `docs:` / `chore:`
- 说明要写清改了什么、为什么；禁止「修复 bug」「优化代码」
