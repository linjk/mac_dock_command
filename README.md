# BarCmd

macOS 菜单栏 App：维护一组长期运行的 shell 命令，查看 PID / 端口 / 日志，并手动启停。用来替代一直挂着的终端窗口。

## 状态

Xcode 工程已建立，菜单栏占位可编译。功能实现按 `ROADMAP.md` 推进。

- 规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`
- 工程：`BarCmd/BarCmd.xcodeproj`，scheme `BarCmd`

## 要求

- macOS 14+
- Xcode（Swift 5.9+）
- 从 Xcode 运行 `BarCmd`，或 `xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build`
- 菜单栏出现图标，无 Dock 图标

配置文件（实现后）：

`~/Library/Application Support/BarCmd/commands.yaml`
