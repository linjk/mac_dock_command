# BarCmd

macOS 菜单栏 App：维护一组长期运行的 shell 命令，查看 PID / 端口 / 日志，并手动启停。用来替代一直挂着的终端窗口。

## 要求

- macOS 14+
- Xcode（Swift 5.9+）

## 运行

用 Xcode 打开 `BarCmd/BarCmd.xcodeproj`，选 scheme `BarCmd`，Run。

菜单栏会出现 template 图标（方括号加播放键），Dock 无图标。也可：

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build
```

## 配置路径

`~/Library/Application Support/BarCmd/commands.yaml`

菜单栏 Popover 底部「打开配置」可在 Finder 中显示该文件。外部改文件后会提示是否重载列表。

## 添加一条命令（最短步骤）

1. 点菜单栏图标，打开 Popover。
2. 点「添加命令」。
3. 填 Name（显示名）和 Command（完整 shell 命令），点「保存」。
4. 点该行的播放按钮启动。

工作目录、环境变量可留空。运行中不能直接编辑或删除，须先停止。

## 文档

- 规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`
- 进度：`ROADMAP.md`
