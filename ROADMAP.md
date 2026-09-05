# Roadmap

## 当前阶段

Task 2 已完成：命令值类型与路径展开可单测。下一步 Task 3（ConfigStore）。

## 已完成

- 产品规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 退出杀进程（需确认）、运行中先停再编辑/删除、无 Dock、无设置页
- 图标选定 C；矢量源：`docs/superpowers/specs/icons/barcmd-app-icon.svg`、`barcmd-menubar-template.svg`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`
- 项目约定：`CLAUDE.md`
- 实现计划：`docs/superpowers/plans/2026-09-02-barcmd-implementation.md`
- Task 1：Xcode 工程、身份、图标（`BarCmd` scheme 可 `xcodebuild` 编译；无占位单测）
- Task 2：`CommandStatus` / `CommandConfig` / `CommandRuntime` / `PathExpand`；`PathExpandTests` 4 例通过

## 进行中

无

## 待办

- 按 plan 实现 MVP（Task 3–12）
- 手动验证：`npx @deepseek-ai/dsh web`、nvm/conda、YAML 外部重载、退出杀进程

## 阻塞

无

## 最近验证

- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PathExpandTests` → RED（`PathExpand` 找不到）后 GREEN（4 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 4 tests, 0 failures）
