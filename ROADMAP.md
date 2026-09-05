# Roadmap

## 当前阶段

Task 6 已完成：login shell 启动参数、独立进程组、SIGTERM→5s→SIGKILL 停止。下一步 Task 7（AppModel）。

## 已完成

- 产品规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 退出杀进程（需确认）、运行中先停再编辑/删除、无 Dock、无设置页
- 图标选定 C；矢量源：`docs/superpowers/specs/icons/barcmd-app-icon.svg`、`barcmd-menubar-template.svg`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`
- 项目约定：`CLAUDE.md`
- 实现计划：`docs/superpowers/plans/2026-09-02-barcmd-implementation.md`
- Task 1：Xcode 工程、身份、图标（`BarCmd` scheme 可 `xcodebuild` 编译；无占位单测）
- Task 2：`CommandStatus` / `CommandConfig` / `CommandRuntime` / `PathExpand`；`PathExpandTests` 4 例通过
- Task 3：`ConfigStore` / `CommandsFile` / `ConfigError`；`ConfigStoreTests` 5 例通过（缺文件写骨架、往返、未知字段忽略、非法 YAML、写后 `.bak`）
- Task 4：`ANSIStripper` / `LogBufferStore`；`ANSIStripperTests` 4 例 + `LogBufferTests` 4 例通过（CSI/OSC/Vite 行、入队前剥离、超 10000 丢最旧、clear 留槽、remove 丢掉）
- Task 5：`PortDetector` / `PortTracker` / `LsofParser`；`LsofClient` 仅 protocol；`PortDetectorTests` 11 例通过（四级正则、拒绝时间/版本、优先级覆盖、交集/最小用户端口/连续空 lsof、`:port (LISTEN)` 解析）。未跑真 `lsof`
- Task 6：`ProcessControlling` / `ProcessSpawner` / `ProcessTree` / `ProcessManager`；`ProcessSpawnerTests` 2 例 + `ProcessManagerTests` 2 例通过（zsh/bash source rc 与 export、echo 退出码 3、stdout+stderr、`sleep 30` 在 8s 内被杀掉）。未接 AppModel

## 进行中

无

## 待办

- 按 plan 实现 MVP（Task 7–12）
- 手动验证：`npx @deepseek-ai/dsh web`、nvm/conda、YAML 外部重载、退出杀进程

## 阻塞

无

## 最近验证

- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PortDetectorTests` → RED（`PortDetector`/`PortTracker`/`LsofParser` 找不到）后 GREEN（11 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 28 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ANSIStripperTests -only-testing:BarCmdTests/LogBufferTests` → RED（`ANSIStripper` 找不到）后 GREEN（8 tests, 0 failures；OSC 正则按用例收紧，未改测试）
- 2026-09-05：`ProcessSpawnerTests` RED（`ProcessSpawner` 找不到）后 GREEN（2 tests）；`ProcessManagerTests` RED（`ProcessManager` 找不到）后 GREEN（2 tests，约 1s，非等满 30s）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 32 tests, 0 failures）
