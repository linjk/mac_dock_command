# BarCmd 架构

**日期：** 2026-09-01  
**状态：** 待实现  
**依据：** `docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`  
**图标源：** `docs/superpowers/specs/icons/barcmd-app-icon.svg`、`barcmd-menubar-template.svg`

本文钉模块边界、进程模型和数据流。产品行为以规格为准；规格里的伪代码若与本文冲突，以本文为准（例如 shell 启动参数、lsof 作用域、Foundation `Process` 没有可用的 `processGroupIdentifier`）。

## 目标与约束

| 项 | 值 |
|----|----|
| 显示名 | `BarCmd` |
| Bundle ID | `com.dorian.barcmd` |
| 最低系统 | macOS 14.0 |
| 语言 | Swift 5.9+ |
| UI | SwiftUI，`MenuBarExtra` + `.menuBarExtraStyle(.window)` |
| 依赖 | 仅 Yams（SPM） |
| 沙盒 | 关闭。任意 cwd、任意 shell、`lsof` 都需要 |
| 形态 | Agent：`LSUIElement = true`，`activationPolicy = .accessory`，无 Dock 图标 |
| 配置 | `~/Library/Application Support/BarCmd/commands.yaml` |
| 版本 | 仓库根目录 `VERSION` 为唯一记录；`scripts/release.sh` 默认补丁 +1，写回 `VERSION` 与 `Info.plist`（`CFBundleVersion` 每次 +1） |

全局约束（实现计划中每项任务默认包含）：非沙盒、无 Dock、退出前停光进程、运行中不可直接编辑/删除、菜单栏图标必须是 template。

## 目录

```
mac_dock_command/
├── CLAUDE.md
├── VERSION
├── ROADMAP.md
├── README.md
├── BarCmd/
│   ├── BarCmd.xcodeproj
│   ├── BarCmd/
│   │   ├── App/
│   │   │   ├── BarCmdApp.swift
│   │   │   ├── AppDelegate.swift          # terminate 协商
│   │   │   └── AppModel.swift             # @MainActor 唯一编排
│   │   ├── Models/
│   │   │   ├── CommandConfig.swift
│   │   │   ├── CommandRuntime.swift
│   │   │   └── CommandStatus.swift
│   │   ├── Services/
│   │   │   ├── LoginItem.swift            # SMAppService 登录项
│   │   │   ├── ProcessManager.swift
│   │   │   ├── ProcessSpawner.swift       # 新进程组 + shell 包装
│   │   │   ├── ProcessTree.swift          # pgid / 子树 PID
│   │   │   ├── LogBuffer.swift
│   │   │   ├── ANSIStripper.swift
│   │   │   ├── PortDetector.swift
│   │   │   └── ConfigStore.swift
│   │   ├── Views/
│   │   │   ├── MenuBarView.swift
│   │   │   ├── CommandRowView.swift
│   │   │   ├── CommandEditSheet.swift
│   │   │   └── LogWindowView.swift
│   │   ├── Resources/
│   │   │   ├── Info.plist
│   │   │   └── BarCmd.entitlements        # 空：无沙盒
│   │   └── Assets.xcassets/
│   │       ├── AppIcon.appiconset/
│   │       └── MenuBarIcon.imageset/      # Render As: Template Image
│   └── BarCmdTests/
│       ├── PortDetectorTests.swift
│       ├── ConfigStoreTests.swift
│       ├── ANSIStripperTests.swift
│       ├── PathExpandTests.swift
│       └── ProcessManagerTests.swift
├── scripts/
│   └── release.sh
└── docs/
```

Xcode 工程放在 `BarCmd/`。测试跑在 host，不跑沙盒。

## 运行时结构

```
                    ┌──────────────────────────┐
                    │  SwiftUI Views            │
                    │  MenuBar / Sheet / Log    │
                    └────────────┬─────────────┘
                                 │ 只谈 AppModel
                    ┌────────────▼─────────────┐
                    │  AppModel (@MainActor)    │
                    │  configs + runtimes       │
                    └─┬──────────┬───────────┬─┘
          save/load   │          │ start/stop │ append/subscribe
          watch       │          │            │
          ┌───────────▼──┐  ┌────▼─────┐  ┌──▼─────────┐
          │ ConfigStore  │  │ Process  │  │ LogBuffer  │
          │ (Yams + FS)  │  │ Manager  │  │ (per id)   │
          └──────────────┘  └────┬─────┘  └──┬─────────┘
                                 │ I/O       │ 每行
                            ┌────▼─────┐  ┌──▼─────────┐
                            │ Spawner  │  │ PortDetect │
                            │ + Tree   │  │ regex+lsof │
                            └──────────┘  └────────────┘
```

规则：

- View 不持有 `Process`、不写文件、不调 `lsof`
- `ProcessManager` / `ConfigStore` / `LogBuffer` 不知道 SwiftUI
- 跨模块只传 `Command.ID`（`UUID`）、值类型配置、值类型运行时快照
- 每个模块必须能单独回答：做什么、怎么调用、依赖谁

## 模块

### `CommandConfig` / `CommandRuntime`

持久化（YAML）与运行时（内存）分开。YAML 不写 status / pid / port。

```swift
struct CommandConfig: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var command: String
    var cwd: String?                 // nil → $HOME；`~` 要展开
    var env: [String: String]        // 在 login shell 之后 export
}

enum CommandStatus: String, Sendable {
    case stopped, starting, running, exited
}

struct CommandRuntime: Equatable, Sendable {
    var status: CommandStatus
    var pid: Int32?
    var pgid: Int32?
    var port: Int?
    var exitCode: Int32?
    var startedAt: Date?
}
```

`id` 只在 UI 添加时 `UUID()`。展示顺序 = YAML 数组顺序。

### `AppModel`（编排，`@MainActor`）

唯一 UI 状态源。`@Observable`。

```swift
@MainActor
@Observable
final class AppModel {
    private(set) var configs: [CommandConfig]
    private(set) var runtimes: [UUID: CommandRuntime]

    func start(_ id: UUID) async
    func stop(_ id: UUID) async
    func stopAll() async
    func add(_ draft: CommandConfig)
    func update(_ config: CommandConfig)           // 调用方已保证非 running
    func delete(_ id: UUID) async                  // 调用方已保证非 running，或先 stop
    func requestEdit(_ id: UUID) async -> Bool     // 运行中弹窗，停止成功返回 true
    func requestDelete(_ id: UUID) async -> Bool
    func openLog(_ id: UUID)
    func revealConfig()
    func requestQuit()
    func applyExternalReload() throws
}
```

`configs[i]` 与 `runtimes[id]` 按 id 关联。缺 runtime 时视为 `stopped`。

### `ProcessSpawner`

把一条命令变成「独立进程组里的 login shell」。Foundation `Process` **不能**当进程组 API 用。

启动参数：

| Shell | `arguments` |
|-------|-------------|
| `zsh`（默认） | `["-l", "-c", "source \"${ZDOTDIR:-$HOME}/.zshrc\" >/dev/null 2>&1 \|\| true; \(exports)\(command)"]` |
| `bash` | `["-l", "-c", "source \"$HOME/.bashrc\" >/dev/null 2>&1 \|\| true; \(exports)\(command)"]` |
| 其他 | `["-l", "-c", "\(exports)\(command)"]` |

说明：

- 可执行文件：`$SHELL`，缺省 `/bin/zsh`
- **不用 `-i`。** `-l` 对 zsh 只加载 `.zprofile`，nvm/conda 常见于 `.zshrc`，所以显式 `source`。`-i` 会启用 job control，无 TTY 时不稳定
- **不要**用 App 自己的 `environment` 覆盖子进程环境。GUI 的 PATH 是 launchd 最小集。让 login shell 自己铺环境
- `command.env` 变成 `-c` 脚本里、source 之后的 `export KEY=VAL;`，保证覆盖 rc 里的同名变量
- `cwd`：展开 `~` 后设 `currentDirectoryURL`；目录不存在 → 启动失败，状态 `exited`，缓冲里写一行错误
- stdout 与 stderr **合并进同一 Pipe**
- `standardInput = FileHandle.nullDevice`，避免读 stdin 的命令把 App 卡住
- `run()` 成功后立刻 `setpgid(pid, pid)`。失败（`EACCES`）不视为启动失败，停止时改走子树杀

```swift
struct SpawnedProcess: Sendable {
    let pid: Int32
    let pgid: Int32          // 成功 setpgid 时 == pid，否则为当前 pgid
    let process: Process     // 非 Sendable，实际由 ProcessManager 持有
}
```

`ProcessManager` 持有 `Process`；Spawner 只负责组装参数和 `setpgid`。

### `ProcessTree`

```swift
enum ProcessTree {
    static func pids(inGroup pgid: Int32) -> [Int32]
    static func descendantPIDs(of pid: Int32) -> [Int32]   // 含自身，BFS
    static func send(_ signal: Int32, toGroup pgid: Int32) -> Bool
    static func send(_ signal: Int32, toPIDs pids: [Int32])
}
```

实现用 `proc_listpids` / `sysctl`，不要解析 `ps` 文本。`lsof` 和停止都用这组 PID。

### `ProcessManager`

```swift
actor ProcessManager {
    func start(config: CommandConfig, cwd: URL, onOutput: @Sendable (UUID, String) -> Void, onExit: @Sendable (UUID, Int32) -> Void) throws
    func stop(id: UUID) async           // SIGTERM → 5s → SIGKILL → 等到 termination
    func stopAll() async                // 并行 stop
    func runtimeSnapshot(id: UUID) -> (pid: Int32, pgid: Int32)?
}
```

状态机（由 AppModel 写 runtime，ProcessManager 只回调）：

```
stopped ──start──► starting ──spawn 成功──► running
                       │                         │
                       │ spawn 失败              │ 进程自己退出
                       ▼                         ▼
                    exited                    exited
running/starting ──stop──► stopped
```

- spawn 成功（`run()` 返回）即 `running`，不等端口
- `onOutput` 每行（已去 ANSI、已按 `\n` 切）切回 MainActor 再进 `LogBuffer` 和 `PortDetector`
- `onExit`：若这次退出是 `stop()` 发起的 → AppModel 写 `stopped` 并清 pid/port/startedAt/exitCode；否则写 `exited`，清 pid/port，保留 exitCode
- 同一 id `running`/`starting` 时 `start` 直接 return，不抛（UI 已禁用）

停止：

1. 若 `pgid == pid`，`killpg(pgid, SIGTERM)`
2. 否则对 `descendantPIDs` 逐个 `SIGTERM`
3. 等 `Process.terminationHandler` 或 5s，先到先结束等待
4. 仍在则对同一组发 `SIGKILL`
5. 再等直到 handler 或最多 2s，然后 AppModel 仍切 `stopped`（防止退出流程卡死）

### 退出

`AppDelegate.applicationShouldTerminate`：

1. 无 starting/running → `.terminateNow`
2. 有 → 弹「有 N 条命令正在运行，退出将停止它们。」「取消」/「退出并停止」
3. 取消 → `.terminateCancel`
4. 确认 → `.terminateLater`，Popover 禁用，`await stopAll()`，再 `NSApp.reply(toApplicationShouldTerminate: true)`

Popover「退出 BarCmd」与 `Cmd+Q` 都走 `NSApp.terminate(nil)`，不要自己 `exit()`。

### `LogBuffer`

```swift
final class LogBufferStore: @unchecked Sendable {
    func append(id: UUID, line: String)
    func lines(id: UUID) -> [String]          // 最多 10_000
    func clear(id: UUID)                      // 只清缓冲，不清进程
    func remove(id: UUID)                     // 删除命令时丢掉
    func publisher(id: UUID) -> any Publisher // 或 AsyncStream
}
```

- 环形 10_000 行，满则丢最旧
- 进程退出后缓冲保留到 App 退出、用户清屏、或命令被删除
- 打开日志窗：先灌现有行，再订增量
- 入缓冲前走 `ANSIStripper`。MVP 不着色

`ANSIStripper`：去掉 CSI（`ESC [` … 字母）和 OSC（`ESC ]` … `BEL`/`ESC \`）。单测用带颜色的 Vite 行。

### `PortDetector`

两路，AppModel 合并成一个 `port: Int?`。

**日志（每行，同步）：** 优先级从高到低，端口 ∈ `[1, 65535]`：

```
https?://(?:127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\]):(\d+)
(?i)listening on(?: port)? (\d+)
(?i)Local:\s+https?://\S+:(\d+)
(?i)server running (?:on|at).*:(\d+)
```

**不做** 裸 `:(\d+)` 兜底（会吃到时间戳和版本号）。

同一命令记住「当前优先级」；更高优先级命中才覆盖。

**lsof（`running` 后每 2s，后台队列）：**

```
lsof -nP -iTCP -sTCP:LISTEN -p <pid1,pid2,...>
```

PID 列表 = `ProcessTree.pids(inGroup:)`，若为空则 `descendantPIDs(of: shellPid)`。只查进程组/子树，禁止只查 shell PID（`npx` 的 node 听端口）。

合并：

1. 日志先到先展示
2. lsof 非空则以 lsof 为准
3. lsof 多个端口：若日志提示端口仍在集合里，用它；否则用 `>= 1024` 的最小端口；再否则用最小端口
4. lsof 为空：保留日志提示；连续 3 次空且无日志提示 → `port = nil`（纯脚本）
5. 进程停止/退出 → `port = nil`

点击 `:port` → `NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!)`。MVP 一律 http。

### `ConfigStore`

```swift
final class ConfigStore {
    func load() throws -> [CommandConfig]
    func save(_ configs: [CommandConfig]) throws
    func startWatching(onExternalChange: @escaping () -> Void)
    func revealInFinder()
}
```

- 目录没有就创建；文件没有就当空列表并写出 `commands: []`
- 写：temp 文件 + `replaceItem`，记 SHA256。FSEvents 命中且哈希相同 → 忽略（避免自己写自己提示重载）
- 外部变更：debounce 300ms，哈希变了才回调。AppModel 弹「配置已更新，是否重载？」
- 解析失败：抛出带行号的错误。启动时：有上次成功快照（内存或 `commands.yaml.bak`）则用快照并弹窗；否则空列表并弹窗。保存成功时覆盖 `.bak`
- 重载与运行中命令：
  - 仍在 YAML 中的 id：更新 `CommandConfig`，**不**重启进程
  - YAML 里没了但仍 `starting`/`running`：留在列表，标记 `removedFromConfig`（Popover 名称旁「已从配置移除」），停止或退出后从列表消失且不写回 YAML
  - YAML 新增 id：插入列表，runtime = stopped
- `save` 不把 `removedFromConfig` 的运行中项写回去

YAML 字段：`id`（UUID 字符串）、`name`、`command`、`cwd`（省略则 nil）、`env`（省略则 `{}`）。未知字段解码忽略，便于以后加 `autoStart`。

### Views

| 文件 | 职责 |
|------|------|
| `MenuBarView` | 列表、底栏（添加 / 登录时启动 / 打开配置 / 退出）、空状态「还没有命令」 |
| `CommandRowView` | 状态点、名称、按钮、副行、PID/port/运行时长 |
| `CommandEditSheet` | 添加与编辑共用（独立窗口，不挂 Extra） |
| `LogWindowView` | 等宽、深色、自动滚底；复制全部、清屏；PID/port/时长 |

编辑窗口（不要用 Extra 上的 `.sheet`：点表单等于点到 Extra 外，Popover 拆除，表单一起关）：

```swift
WindowGroup(id: "command-edit", for: UUID.self) { $id in
    CommandEditSheet(commandID: id)
}
.defaultSize(width: 460, height: 360)
```

`presentEditor` 写 `pendingEdit` 并 `openWindow(id: "command-edit", value: id)`。同 id 聚焦已有窗口。取消 / 保存 / 关窗清 `pendingEdit`。

日志窗口：

```swift
WindowGroup(id: "command-log", for: UUID.self) { $id in
    LogWindowView(commandID: id)
}
.defaultSize(width: 720, height: 480)
```

`openLog` 调 `openWindow(id: "command-log", value: id)`。同 id 聚焦已有窗口。关窗不停进程。

Popover 宽度约 420pt。列表按行数给明确高度（单行约 76pt，最高 360pt），`ScrollView` 不能没高度，否则 Extra 会裁掉第二条。打开 Extra 时 `applyExternalReload`，磁盘有的命令必须出现在列表。一行五个按钮挤不下时：主行保留 ▶ ⏹ 📋，✎ 🗑 放上下文菜单或 hover 溢出，但 **必须可发现**。优先：主行五个图标按钮，名称 `lineLimit(1)`。

`starting`：灰点 + `ProgressView` 小转圈。绿/灰/红对应 running/stopped/exited。

编辑/删除确认用 `NSAlert` 或 `.confirmationDialog`，文案按规格。`requestEdit`/`requestDelete` 封装「是否要先停」。

## 线程

| 工作 | 线程 |
|------|------|
| 全部 SwiftUI、AppModel、改 runtime | MainActor |
| Pipe `readabilityHandler` | Foundation 后台；只做切行 + 去 ANSI，再 `MainActor.assumeIsolated` 或 `await MainActor.run` |
| lsof / ProcessTree | `DispatchQueue` 标签 `com.dorian.barcmd.port`，2s 一轮，结果回 MainActor |
| YAML 读写 | MainActor 即可（文件小）；FSEvents 回调切回 MainActor |
| `stop` 等待 | ProcessManager actor / Task，不要阻塞主线程 |

禁止在 readabilityHandler 里直接改 `@Observable`。

## 身份、权限、图标

`Info.plist`：

- `CFBundleName` / `CFBundleDisplayName` = `BarCmd`
- `CFBundleIdentifier` = `com.dorian.barcmd`
- `LSMinimumSystemVersion` = `14.0`
- `LSUIElement` = `true`
- `NSHighResolutionCapable` = `true`

`BarCmd.entitlements`：空 dict。不要 `com.apple.security.app-sandbox`。Hardened Runtime / 公证放到分发阶段，MVP 只本地 Debug。

图标（已选定 C）：

| 资源 | 源文件 | 用法 |
|------|--------|------|
| App | `docs/superpowers/specs/icons/barcmd-app-icon.svg` | 导出 1024 进 `AppIcon.appiconset`（以及 Xcode 需要的中间尺寸） |
| 菜单栏 | `docs/superpowers/specs/icons/barcmd-menubar-template.svg` | `MenuBarIcon.imageset`，**Render As: Template Image**，提供 18pt/@1x 与 36pt/@2x（或单份 PDF） |

颜色：底 `#243447`，括号 `#F2F2F7`，三角 `#30D158`。菜单栏 glyph 只有黑+透明，无 squircle 底。

`MenuBarExtra` 的 `label` 用 `Image("MenuBarIcon")`，不要 SF Symbol。

登录自启（App 级，不是命令 `autoStart`）：

- `LoginItemControlling`：`isEnabled` / `requiresApproval` / `setEnabled(_:)`
- 实现：`SMAppService.mainApp.register()` / `unregister()`；`isEnabled` 看 `status == .enabled`
- `UserDefaults` 键 `loginItemPrompted`：首次 Extra 出现问一次「登录 Mac 时启动 BarCmd？」
- `requiresApproval` 时 `prompter.alert`「请在系统设置 → 通用 → 登录项中允许 BarCmd」
- 登录项跟 Bundle ID `com.dorian.barcmd`；覆盖 `/Applications/BarCmd.app` 不必重注册
- Debug / DerivedData 里的包登录项不可靠，以 `/Applications` 的 Release 为准

`MenuBarExtra` 关掉后不会因为 `configs` 变了而重算 body（编辑独立窗口会拆掉 Extra）。`BarCmdApp.body` 必须直接读 `model.configs`，并把 Extra 内容 `.id` 绑到命令 ID 列表，否则保存成功、YAML 有了，列表仍是旧的。

## 错误到 UI

| 原因 | 用户看到 |
|------|----------|
| spawn 抛错 / cwd 不存在 | `exited`，日志一行中文原因 |
| 命令秒退（端口占用等） | `exited` + 真实 stderr |
| YAML 坏 | 弹窗行号，用 .bak 或空列表 |
| 停止超时后 SIGKILL | 仍 `stopped`，不弹窗 |
| lsof 失败 | 忽略这一轮，保留上次 port |

## 测试

XCTest（随 app target，macOS 14）。不引入测试第三方库。

| 文件 | 必须覆盖 |
|------|----------|
| `PortDetectorTests` | 四级正则优先级；拒绝 `12:34:56`、`v1.2.3`；多端口合并规则 |
| `ANSIStripperTests` | CSI / OSC 剥净，正文保留 |
| `PathExpandTests` | `~`、`~/src`、绝对路径 |
| `ConfigStoreTests` | 编解码、未知字段忽略、原子写后哈希稳定 |
| `ProcessManagerTests` | `sleep 30` 能停；`echo hi; exit 3` → exited + code 3；stdout/stderr 都能进缓冲 |

手动（实现完成后写进 ROADMAP「最近验证」）：`npx @deepseek-ai/dsh web`、conda/nvm PATH、外部改 YAML、退出确认杀进程。

## 实现顺序

每一项结束时要能编译或能跑对应测试，不要平行铺开 UI 和进程。

1. 工程骨架 + 空 entitlements + 图标资源
2. `CommandConfig` + `ConfigStore` + 单测
3. `ANSIStripper` + `LogBuffer` + 单测
4. `PortDetector` 正则 + 单测
5. `ProcessSpawner` / `ProcessTree` / `ProcessManager` + 集成测
6. `AppModel` 状态机（含退出、编辑删除闸门）
7. Popover UI + Sheet
8. 日志 `WindowGroup`
9. lsof 轮询接上
10. FSEvents 重载
11. 手动全链路

实现计划：`docs/superpowers/plans/2026-09-02-barcmd-implementation.md`。
