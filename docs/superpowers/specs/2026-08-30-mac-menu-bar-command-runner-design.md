# macOS 菜单栏命令运行器（BarCmd）设计规格

**日期：** 2026-08-30  
**状态：** 待实现  
**仓库：** `mac_dock_command`

## 背景与目标

开发者在 macOS 上运行 `npx @deepseek-ai/dsh web` 等前台命令时，必须保持一个终端窗口常驻。本工具提供菜单栏 App，替代「挂终端」的方式，统一管理多条长期运行的 shell 命令。

### 目标

- 菜单栏常驻，维护命令列表
- 展示每条命令的文本、PID、端口号、运行状态
- 手动启动 / 停止命令
- 实时查看 stdout/stderr 日志（独立窗口）
- UI 与 YAML 配置文件双向同步

### 非目标（MVP 不做）

- 登录自启 / 命令 autoStart
- 日志搜索 / 过滤
- 命令分组 / 标签
- 同一条命令多实例
- iCloud 配置同步

## 需求摘要

| 维度 | 决策 |
|------|------|
| 命令类型 | 开发服务 + 任意长期 shell 命令 |
| 日志 | 必须，实时 stdout/stderr |
| 配置 | UI 为主 + YAML 双向同步 |
| 启动行为 | 手动，App 与命令均不自动启动 |
| 端口 | 日志正则解析 + lsof 校验 |
| Shell 环境 | login shell（`-l`），继承 nvm/conda/PATH |
| UI 形态 | 菜单栏 Popover 列表 + 独立日志窗口（可多开） |
| 技术方案 | Swift 原生（SwiftUI + MenuBarExtra） |

## 架构

```
┌─────────────────────────────────────────────────┐
│  MenuBarExtra（状态栏图标 + Popover 命令列表）    │
└──────────────┬──────────────────────────────────┘
               │ 启停 / 打开日志窗口
┌──────────────▼──────────────────────────────────┐
│  ProcessManager（核心）                          │
│  · spawn: $SHELL -l -c "<command>"              │
│  · 捕获 stdout/stderr → LogBuffer（环形缓冲）    │
│  · 监控 exit code，更新状态                      │
│  · stop: SIGTERM → 5s 超时 → SIGKILL            │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│  PortDetector                                    │
│  · 正则解析日志里的 URL/端口                      │
│  · lsof -Pan -p PID 校验实际监听端口              │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│  ConfigStore（YAML 双向同步）                    │
│  ~/Library/Application Support/BarCmd/          │
│    commands.yaml                                 │
│  · UI 改动 → 写文件                              │
│  · 外部改文件 → FSEvents → 通知重载              │
└─────────────────────────────────────────────────┘

        ┌─────────────────────┐
        │  LogWindow（独立窗口） │  ← 每个命令最多一个，可聚焦
        │  · 实时滚动日志        │
        │  · 复制 / 清屏         │
        │  · 显示 PID / 端口     │
        └─────────────────────┘
```

### 模块职责

| 模块 | 职责 |
|------|------|
| `MenuBarExtra` | 状态栏入口、Popover 命令列表、启停与打开日志 |
| `ProcessManager` | 子进程生命周期、信号、进程组管理 |
| `LogBuffer` | 每命令环形缓冲（10,000 行），向 LogWindow 推送 |
| `PortDetector` | 日志行正则 + lsof 轮询，合并为展示端口 |
| `ConfigStore` | YAML 读写、FSEvents 监听、UI 同步 |
| `LogWindow` | 独立 SwiftUI 窗口，等宽字体实时日志 |

## 数据模型

### 持久化配置（`commands.yaml`）

路径：`~/Library/Application Support/BarCmd/commands.yaml`

```yaml
commands:
  - id: "dsh-web"
    name: "DSH Web"
    command: "npx @deepseek-ai/dsh web"
    cwd: "~"           # 可选，默认 $HOME
    env: {}            # 可选，追加环境变量 key: value
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | ✓ | 唯一标识，UUID 或 slug |
| `name` | ✓ | Popover 显示名 |
| `command` | ✓ | 完整 shell 命令字符串 |
| `cwd` | | 工作目录，`~` 展开为 `$HOME` |
| `env` | | 追加到 login shell 环境的键值对 |

`autoStart` 等字段可在后续版本扩展；MVP 不包含。

### 运行时状态（内存 only）

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | enum | `stopped` / `starting` / `running` / `exited` |
| `pid` | Int? | 主进程 PID |
| `port` | Int? | 检测到的监听端口 |
| `exitCode` | Int32? | 退出码，`exited` 时有效 |
| `startedAt` | Date? | 启动时间，用于运行时长展示 |

## UI 设计

### Popover 命令列表

每条命令一行卡片：

- **状态指示：** 绿 `running`、灰 `stopped`、红 `exited`
- **主行：** name + 操作按钮（▶ 启动 / ⏹ 停止 / 📋 日志）
- **副行：** 完整 command 文本（可截断 + tooltip）
- **状态行：** `PID · :port · status`；无端口时不显示端口段
- **:port** 可点击，系统浏览器打开 `http://127.0.0.1:{port}`

底部操作：

- **＋ 添加命令** — Sheet 表单
- **⚙ 设置** — 预留（MVP 可仅占位或省略）
- **📂 打开配置** — Finder Reveal `commands.yaml`

按钮规则：

- `stopped` / `exited`：▶ 可用，⏹ 禁用
- `running`：▶ 禁用，⏹ 可用
- 已 `running` 时不允许重复启动

### 添加 / 编辑 Sheet

| 字段 | 必填 |
|------|------|
| Name | ✓ |
| Command | ✓ |
| Working Directory | |
| Environment Variables | |

保存后立即写入 YAML。若该命令正在运行，提示「需重启后生效」，不自动重启。

### 独立日志窗口

- 每命令最多一个窗口；再次点 📋 聚焦已有窗口
- 等宽字体、深色背景；新输出自动滚到底部
- 工具栏：复制全部、清屏（仅 UI）、PID / 端口 / 运行时长
- 关闭窗口不终止进程；可从 Popover 重新打开

## 进程管理

### 启动

```swift
let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
process.executableURL = URL(fileURLWithPath: shell)
process.arguments = ["-l", "-c", command.command]
process.currentDirectoryURL = resolvedCWD
process.environment = loginShellEnv.merging(command.env)
// stdout + stderr 合并到单一 Pipe
```

要点：

- `-l` 加载 login shell 配置（`.zprofile` / `.zshrc`），保证 nvm、conda、PATH
- stdout 与 stderr **合并捕获**，避免 dev server 只向 stderr 输出端口时漏检
- 使用进程组（`processGroupIdentifier`），便于停止时杀掉 `npx` 等 fork 出的子进程

### 停止

1. 向进程组发送 `SIGTERM`
2. 等待最多 5 秒
3. 仍存活则 `SIGKILL`
4. 状态置 `stopped`，清空 PID / port

## 端口检测

### 1. 日志正则（每行实时）

优先级从高到低：

```
http://127.0.0.1:(\d+)
http://localhost:(\d+)
listening on port (\d+)
[Ss]erver running on.*:(\d+)
:(\d+)                    # 兜底，最低优先级
```

首次匹配到有效端口即更新 UI；后续更高优先级匹配可覆盖。

### 2. lsof 校验（running 后每 2s）

```bash
lsof -Pan -p <PID> -iTCP -sTCP:LISTEN
```

- 日志解析先到先展示
- 与 lsof 不一致时以 **lsof 为准**
- 无 TCP 监听端口的命令（纯脚本）不显示端口，非错误

## 日志缓冲

- 每命令内存环形缓冲，**最近 10,000 行**
- 超出丢弃最旧行
- 日志窗口订阅缓冲增量；打开窗口时先灌入已有内容
- 进程退出后缓冲保留至 App 退出或用户清屏

## 配置同步

| 方向 | 行为 |
|------|------|
| UI → 文件 | 增删改后立即写 `commands.yaml` |
| 文件 → UI | FSEvents 检测变更 → 通知「配置已更新，是否重载？」→ 确认后刷新 |
| 运行中变更 | 不自动重启；可标记「待重启」（可选 UI 提示） |

YAML 解析失败：启动时弹窗提示错误行号，回退到上次有效配置（若存在）；否则空列表。

## 错误处理

| 场景 | 处理 |
|------|------|
| 命令立即退出 | `exited`（红），日志窗口展示 stderr |
| 端口被占用 | 进程报错退出，Popover 显示 `exited` |
| YAML 格式错误 | 见配置同步 |
| App 意外退出 | 子进程可能残留；下次启动可选检测同 command/端口占用并提示（MVP：文档说明，检测为增强项） |
| 重复启动 | `running` 时禁用 ▶ |

## 测试策略

| 层级 | 内容 |
|------|------|
| 单元 | PortDetector 正则、YAML 编解码、路径展开 |
| 集成 | ProcessManager 启停简单 `sleep` / `echo` 命令 |
| 手动 | `npx @deepseek-ai/dsh web` 全链路：启动、端口、浏览器、停止、日志 |
| 手动 | 外部编辑 YAML 后 FSEvents 重载 |
| 手动 | conda/nvm 环境下命令能否找到二进制 |

## 项目结构（建议）

```
mac_dock_command/
├── BarCmd/                    # Xcode 工程
│   ├── BarCmdApp.swift
│   ├── Models/
│   ├── Services/
│   │   ├── ProcessManager.swift
│   │   ├── PortDetector.swift
│   │   ├── LogBuffer.swift
│   │   └── ConfigStore.swift
│   └── Views/
│       ├── MenuBarView.swift
│       ├── CommandRowView.swift
│       ├── CommandEditSheet.swift
│       └── LogWindowView.swift
├── docs/
└── README.md
```

## 技术栈

- **语言：** Swift 5.9+
- **UI：** SwiftUI，`MenuBarExtra`
- **最低系统：** macOS 14.0（Sonoma，MenuBarExtra 成熟）
- **依赖：** Yams（YAML）；无其他第三方运行时

## 开放问题（实现阶段确认）

1. App 显示名与 Bundle ID（如 `com.dorian.barcmd`）
2. 菜单栏图标：SF Symbol `terminal` 或自定义
3. App 崩溃后孤儿进程：MVP 仅文档说明 vs 启动时 `lsof` 扫描提示

---

*本规格由 brainstorming 流程产出，用户已于 2026-08-30 确认。*
