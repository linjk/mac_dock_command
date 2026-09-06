# Roadmap

## 当前阶段

发布脚本 + App 登录自启。命令仍手动启停。手动清单未全部手测，**不能**把阶段标成「MVP 已实现」。

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
- Task 7：`UserPrompter` / `AppModel`；`AppModelTests` 12 例通过（启停状态机、cwd 缺失中文日志、编辑/删除闸门、外部 YAML 删掉运行中命令先挂起、lsof 端口不被无端口日志行清掉）。无 SwiftUI；`requestQuit` 仅 `NSApp.terminate(nil)`
- Task 8：`MenuBarView` / `CommandRowView` / `CommandEditSheet` / `AlertPrompter`；空 `AppDelegate` 仅 `.accessory`；`load()` 失败写 `loadError` 并试 `.bak`。无日志 WindowGroup（Task 9）；退出确认留给 Task 11
- Task 9：`LogWindowView` + `WindowGroup(id: "command-log")`；📋 经 `openWindow` 打开；关窗不停进程。未手测 `echo line1; echo line2; sleep 5`
- Task 10：`LsofCommand` / `RealLsofClient` + AppModel 每 2s 进程组 lsof；`LsofClientTests` 3 例通过。空 pid 不 spawn；非 0 退出当本轮 `[]`。日志行经 `PortDetector.merge` 更新端口，不再用裸 `ingestLogLine` 覆盖 lsof 结果。未手测 `npx` 外壳子进程端口
- Task 11：目录 + 文件 `DispatchSource` 监听 YAML；`save`/`load`/`startWatching` 对齐 `lastWrittenHash`，哈希相同不回调；外部改写 debounce 300ms 后 `confirmReload` → `applyExternalReload`（`isQuitting` 忽略；reload 失败 alert）。`applicationShouldTerminate`：无运行中 `terminateNow`，否则 `confirmQuitSync`，取消 `terminateCancel`，确认则 `isQuitting` + `terminateLater` + `stopAll`。未手测外部改 yaml / Cmd+Q
- Task 12：全量 `xcodebuild … test` 通过；README 写明 Xcode 打开工程、配置路径、最短添加命令步骤。手动 dsh / nvm / 退出杀进程 / 运行中先停 见「待办」与「最近验证」
- App 登录自启：`SMAppService` + 底栏「登录时启动」+ 首次确认；命令仍无 autoStart
- `scripts/release.sh`：根目录 `VERSION` 为当前版本；不传参补丁 +1 并写回 `VERSION` / Info.plist；打 Release zip；`--install` 覆盖 `/Applications`（未在本机跑过）

## 进行中

无

## 待办

- 手动验证（待确认）：升级后菜单栏只应有一个图标（`SingleInstanceGuard` 启动时结束同 Bundle ID 旧进程）。若已双图标：`killall BarCmd` 后只开 `/Applications/BarCmd.app`
- 手动验证（待确认）：打开菜单栏应同时看到 echo-test 与 DSH（打开 Extra 会 `applyExternalReload`，列表按行数定高；无 Accessibility，未手点）
- 手动验证（待确认）：再次打开编辑窗口后，点 Name / Command 输入框，窗口应保持打开并可输入（已从 Extra `.sheet` 改为独立 `WindowGroup`；无 Accessibility，未手点）
- 手动验证（待确认）：`npx @deepseek-ai/dsh web` 启停与 `:port`、nvm/conda 命令里能找到二进制、有 running 时退出杀进程组、运行中点编辑/删除必须先停、菜单栏 glyph 肉眼确认
- 手动验证（部分）：外部改 YAML 会弹出重载确认框（本机已见到 260×176 对话框；未点「重载」，列表是否更新未确认）

## 阻塞

无 Accessibility 权限，无法用脚本点菜单栏 extra / 对话框按钮。本机有 iBar Pro，菜单栏 extra 可能被收纳，截图未辨认出 `[▶]`。

## 最近验证

- 2026-09-07：Popover 状态行显示运行时长（`RuntimeDurationLabel`，运行中实时计时，启动中仍显示「启动中」）。全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 65 tests, 0 failures）。手点 **待确认**
- 2026-09-05：`./scripts/release.sh` 打出 `dist/BarCmd-0.1.1.zip`。`VERSION` / Info.plist 现为 `0.1.1`（build 2）。echo 紧贴中文括号导致 `set -u` 的问题已用 `printf` 修掉。
- 2026-09-05：当前版本改记仓库根目录 `VERSION`（`0.1.0`）。`release.sh` 默认从该文件补丁 +1，写回 `VERSION` 与 Info.plist；两处不一致则失败。`bash -n scripts/release.sh` 通过。未跑完整打包。
- 2026-09-05：App 登录自启（`SMAppService` + 底栏开关 + 首次确认）与 `scripts/release.sh`（Info.plist 升版、Release zip、`--install`）。`AppModelTests` 新增 4 例登录项；`bash -n scripts/release.sh` 通过。全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 65 tests, 0 failures）。未跑 `--install`。
- 2026-09-05：已重启 21:28 Debug 包仍看不到 DSH。YAML / `.bak` 均有 echo-test + DSH。Extra 里无高度的 `ScrollView` 会裁第二条；打开时也不从磁盘对齐。改为按行数定高 + `onAppear` 调 `applyExternalReload`，模型只挂 `AppDelegate`。新增 `testApplyExternalReloadPicksUpCommandWrittenToDisk`。全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 61 tests, 0 failures）。手点菜单栏 **待确认**
- 2026-09-05：添加命令后 YAML 有 DSH，列表不刷新。根因是编辑独立窗口拆掉 Extra 后，`MenuBarExtra` 复用旧 body，不重读 `configs`。`BarCmdApp.body` 直接读命令 ID，Extra 内容 `.id` 绑到该列表。磁盘 `commands.yaml` 已含 echo-test + DSH。全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 60 tests, 0 failures）。手点菜单栏 **待确认**
- 2026-09-05：编辑表单再点输入即关。根因是 `.sheet` 挂在 `MenuBarExtra` 上，点表单等于点 Extra 外，Popover 拆除。改为 `WindowGroup(id: "command-edit")` + `presentEditor` / `dismissEditor`。`AppModelTests` 20/0；全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 60 tests, 0 failures）。手点输入框 **待确认**
- 2026-09-05：整分支评审三项 Important：`start`/`handleExit` 清空 PortTracker；ProcessManager 按 pid 匹配退出并等 teardown；`persist` 失败 `prompter.alert`「保存配置失败」。覆盖 `AppModelTests` 16/0 + `ProcessManagerTests` 3/0；全量 `xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → **TEST SUCCEEDED**（Executed 56 tests, 0 failures）
- 2026-09-02：Task 12 全量 `xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → **TEST SUCCEEDED**（Executed 53 tests, 0 failures）
- 2026-09-02：启动 Debug `BarCmd.app`（pid 曾为 44478）。Dock 常规应用列表无 BarCmd；进程 `background only`。`LSUIElement` + `setActivationPolicy(.accessory)` 与此一致
- 2026-09-02：外部改写 `~/Library/Application Support/BarCmd/commands.yaml` 后，BarCmd 弹出约 260×176 窗口（重载确认）。未点「重载」，列表是否更新 **待确认**
- 2026-09-02：`npx @deepseek-ai/dsh web` 经 App 启动、日志 URL、`:port` 开浏览器、停止后进程与端口消失 — **待确认**（无辅助功能，无法点启动；未在 App 内跑 dsh）
- 2026-09-02：当前 conda/nvm 环境里 `node -v` / `which npx` 经 BarCmd 命令能找到二进制 — **待确认**（本机 login shell 有 nvm node v24.14.0 与 npx；未在 App 命令里跑）
- 2026-09-02：有 running 时退出 App，进程组消失 — **待确认**（未启动长期命令再退）
- 2026-09-02：运行中点编辑/删除必须先停 — **待确认**（仅有单测，未手点）
- 2026-09-02：菜单栏 template `[▶]` 肉眼确认 — **待确认**（资源 `template-rendering-intent` 已设；截图未辨认出 glyph，可能被 iBar Pro 收纳）
- 2026-09-05：Task 11 review：`load`/`startWatching` 对齐 `lastWrittenHash`；`beginWatching` 忽略 `isQuitting` 并 catch reload 错误。`ConfigWatchTests` 4/0、`AppModelTests` 14/0；全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 53 tests, 0 failures）
- 2026-09-05：Task 11 `ConfigWatchTests` RED（`startWatching` 找不到）后 GREEN（2 tests, 0 failures）；全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 49 tests, 0 failures）
- 2026-09-05：Task 10 review：`handleOutput` 改为 `PortDetector.merge`；`AppModelTests` RED（无端口日志行把 5173 清成 nil）后 GREEN（12 tests, 0 failures）；全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 47 tests, 0 failures）
- 2026-09-05：Task 10 `xcodebuild … test -only-testing:BarCmdTests/LsofClientTests` → RED（`LsofCommand`/`RealLsofClient` 找不到）后 GREEN（3 tests, 0 failures）；与 AppModelTests 合计 13/0；全量 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 45 tests, 0 failures）
- 2026-09-05：Task 9 `xcodebuild … test` → **TEST SUCCEEDED**（Executed 42 tests, 0 failures）；`xcodebuild … build` → **BUILD SUCCEEDED**
- 2026-09-05：`pendingEdit` 收到 `AppModel` 后 `AppModelTests` 10/0、全量 42/0，`** TEST SUCCEEDED **`
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`（Task 8 Popover / Sheet / AlertPrompter）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 42 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/AppModelTests` → RED（`AppModel`/`UserPrompter` 找不到）后 GREEN（10 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 42 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PortDetectorTests` → RED（`PortDetector`/`PortTracker`/`LsofParser` 找不到）后 GREEN（11 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 28 tests, 0 failures）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ANSIStripperTests -only-testing:BarCmdTests/LogBufferTests` → RED（`ANSIStripper` 找不到）后 GREEN（8 tests, 0 failures；OSC 正则按用例收紧，未改测试）
- 2026-09-05：`ProcessSpawnerTests` RED（`ProcessSpawner` 找不到）后 GREEN（2 tests）；`ProcessManagerTests` RED（`ProcessManager` 找不到）后 GREEN（2 tests，约 1s，非等满 30s）
- 2026-09-05：`xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`（Executed 32 tests, 0 failures）
