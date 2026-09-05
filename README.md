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

## 发布包

当前版本看仓库根目录 `VERSION`（现在是 `0.1.0`）。`./scripts/release.sh` 不传版本号就自动补丁 +1，并写回 `VERSION` 和 `Info.plist`。`CFBundleVersion` 每次 +1。两处不一致会直接失败。不自动 commit / tag。

```bash
cat VERSION                       # 看当前版本
./scripts/release.sh              # 0.1.0 → 0.1.1，生成 zip
./scripts/release.sh 0.2.0        # 跳到指定版本（大改才用手写）
./scripts/release.sh --install    # 自动升补丁后覆盖 /Applications/BarCmd.app 并打开
```

`--install` 会结束正在运行的 BarCmd，不删 `~/Library/Application Support/BarCmd/commands.yaml`。Adhoc 签名，未公证；Gatekeeper 可能提示。登录项请用 `/Applications` 里这份，并在菜单栏打开「登录时启动」。Debug / Xcode Run 的包登录项不可靠。

## 文档

- 规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`
- 进度：`ROADMAP.md`
