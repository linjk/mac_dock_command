import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var configs: [CommandConfig] = []
    private(set) var runtimes: [UUID: CommandRuntime] = [:]
    var isQuitting = false
    private(set) var loadError: String?
    var pendingEdit: CommandConfig?

    var runningCount: Int {
        runtimes.values.filter { $0.status == .running || $0.status == .starting }.count
    }

    var openLogWindow: (UUID) -> Void

    let logs: LogBufferStore

    var lsof: LsofClient

    private let store: ConfigStore
    private let processes: ProcessControlling
    private let prompter: UserPrompter
    private var stoppingIDs: Set<UUID> = []
    private var portTrackers: [UUID: PortTracker] = [:]
    private var portPollTasks: [UUID: Task<Void, Never>] = [:]
    private var consecutiveEmptyLsof: [UUID: Int] = [:]
    private var lastLsofPorts: [UUID: [Int]] = [:]

    init(
        store: ConfigStore,
        processes: ProcessControlling,
        logs: LogBufferStore,
        prompter: UserPrompter,
        openLogWindow: @escaping (UUID) -> Void = { _ in },
        lsof: LsofClient = RealLsofClient()
    ) {
        self.store = store
        self.processes = processes
        self.logs = logs
        self.prompter = prompter
        self.openLogWindow = openLogWindow
        self.lsof = lsof
        do {
            configs = try store.load()
        } catch {
            loadError = error.localizedDescription
            configs = (try? store.loadBackup()) ?? []
        }
        for config in configs {
            runtimes[config.id] = CommandRuntime()
        }
    }

    func runtime(_ id: UUID) -> CommandRuntime {
        runtimes[id] ?? CommandRuntime()
    }

    func presentLoadErrorIfNeeded() async {
        guard let message = loadError else { return }
        loadError = nil
        await prompter.alert(title: "配置加载失败", message: message)
    }

    func start(_ id: UUID) async {
        let status = runtime(id).status
        if status == .starting || status == .running { return }
        guard let config = configs.first(where: { $0.id == id }) else { return }

        var r = runtime(id)
        r.status = .starting
        r.exitCode = nil
        runtimes[id] = r

        let cwd = PathExpand.expand(config.cwd)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory)
        if !exists || !isDirectory.boolValue {
            logs.append(id: id, line: "工作目录不存在：\(cwd.path)")
            r.status = .exited
            runtimes[id] = r
            return
        }

        do {
            try await processes.start(
                config: config,
                cwd: cwd,
                onOutput: { [weak self] id, line in
                    Task { @MainActor in
                        self?.handleOutput(id: id, line: line)
                    }
                },
                onExit: { [weak self] id, code in
                    Task { @MainActor in
                        self?.handleExit(id: id, code: code)
                    }
                }
            )
            guard runtime(id).status == .starting else { return }
            r = runtime(id)
            if let snap = await processes.runtimeSnapshot(id: id) {
                r.pid = snap.pid
                r.pgid = snap.pgid
            }
            guard runtime(id).status == .starting else { return }
            r.startedAt = Date()
            r.status = .running
            runtimes[id] = r
            startPortPolling(id)
        } catch {
            logs.append(id: id, line: "启动失败：\(error.localizedDescription)")
            r = runtime(id)
            r.status = .exited
            runtimes[id] = r
        }
    }

    func stop(_ id: UUID) async {
        let status = runtime(id).status
        guard status == .running || status == .starting else { return }
        stoppingIDs.insert(id)
        await processes.stop(id: id)
        if stoppingIDs.contains(id) {
            handleExit(id: id, code: 0)
        }
    }

    func stopAll() async {
        let ids = runtimes.compactMap { key, value -> UUID? in
            (value.status == .running || value.status == .starting) ? key : nil
        }
        for id in ids {
            stoppingIDs.insert(id)
        }
        await processes.stopAll()
        for id in ids where stoppingIDs.contains(id) {
            handleExit(id: id, code: 0)
        }
    }

    func add(_ draft: CommandConfig) {
        configs.append(draft)
        if runtimes[draft.id] == nil {
            runtimes[draft.id] = CommandRuntime()
        }
        persist()
    }

    func update(_ config: CommandConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        }
        persist()
    }

    func delete(_ id: UUID) async {
        removeConfig(id)
        persist()
    }

    func requestEdit(_ id: UUID) async -> Bool {
        let status = runtime(id).status
        if status == .running || status == .starting {
            let name = configs.first(where: { $0.id == id })?.name ?? ""
            guard await prompter.confirmStopForEdit(name: name) else { return false }
            await stop(id)
        }
        pendingEdit = configs.first(where: { $0.id == id })
        return true
    }

    func requestDelete(_ id: UUID) async -> Bool {
        let status = runtime(id).status
        if status == .running || status == .starting {
            let name = configs.first(where: { $0.id == id })?.name ?? ""
            guard await prompter.confirmStopForDelete(name: name) else { return false }
            await stop(id)
        }
        let name = configs.first(where: { $0.id == id })?.name ?? ""
        guard await prompter.confirmDelete(name: name) else { return false }
        removeConfig(id)
        persist()
        return true
    }

    func openLog(_ id: UUID) {
        openLogWindow(id)
    }

    func revealConfig() {
        store.revealInFinder()
    }

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func beginWatching() {
        store.startWatching { [weak self] in
            Task { @MainActor in
                guard let self, !self.isQuitting else { return }
                do {
                    if await self.prompter.confirmReload() {
                        try self.applyExternalReload()
                    }
                } catch {
                    self.loadError = error.localizedDescription
                    await self.prompter.alert(title: "配置加载失败", message: error.localizedDescription)
                }
            }
        }
    }

    func applyExternalReload() throws {
        let fresh = try store.load()
        let freshIDs = Set(fresh.map(\.id))

        var hung: [CommandConfig] = []
        for config in configs {
            let status = runtime(config.id).status
            if (status == .running || status == .starting) && !freshIDs.contains(config.id) {
                var r = runtime(config.id)
                r.removedFromConfig = true
                runtimes[config.id] = r
                hung.append(config)
            }
        }

        let surviving = freshIDs.union(hung.map(\.id))
        for id in Array(runtimes.keys) where !surviving.contains(id) {
            cancelPortPolling(id)
            runtimes[id] = nil
            logs.remove(id: id)
            portTrackers[id] = nil
        }
        for config in fresh where runtimes[config.id] == nil {
            runtimes[config.id] = CommandRuntime()
        }
        configs = fresh + hung
    }

    private func handleOutput(id: UUID, line: String) {
        logs.append(id: id, line: line)
        var tracker = portTrackers[id] ?? PortTracker()
        _ = tracker.ingestLogLine(line)
        portTrackers[id] = tracker
        applyMergedPort(id)
    }

    private func handleExit(id: UUID, code: Int32) {
        let current = runtime(id).status
        guard current == .running || current == .starting else { return }
        cancelPortPolling(id)
        let requestedStop = stoppingIDs.contains(id)
        stoppingIDs.remove(id)
        var r = runtime(id)
        r.pid = nil
        r.pgid = nil
        r.port = nil
        if requestedStop {
            r.status = .stopped
            r.exitCode = nil
            r.startedAt = nil
        } else {
            r.status = .exited
            r.exitCode = code
        }
        runtimes[id] = r
        if r.removedFromConfig {
            configs.removeAll { $0.id == id }
            runtimes[id] = nil
            logs.remove(id: id)
            portTrackers[id] = nil
        }
    }

    func pollPortsOnce(id: UUID) async {
        await pollPorts(id: id)
    }

    private func startPortPolling(_ id: UUID) {
        cancelPortPolling(id)
        portPollTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.pollPorts(id: id)
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollPorts(id: UUID) async {
        guard runtime(id).status == .running else {
            cancelPortPolling(id)
            return
        }
        guard let snapshot = await processes.runtimeSnapshot(id: id) else { return }

        let client = lsof
        let ports: [Int]
        do {
            ports = try await Task.detached {
                let groupPIDs = ProcessTree.pids(inGroup: snapshot.pgid)
                let pids = groupPIDs.isEmpty ? ProcessTree.descendantPIDs(of: snapshot.pid) : groupPIDs
                return try client.listeningPorts(pids: pids)
            }.value
        } catch {
            return
        }

        guard runtime(id).status == .running else { return }

        lastLsofPorts[id] = ports
        if ports.isEmpty {
            consecutiveEmptyLsof[id, default: 0] += 1
        } else {
            consecutiveEmptyLsof[id] = 0
        }
        applyMergedPort(id)
    }

    private func applyMergedPort(_ id: UUID) {
        var r = runtime(id)
        r.port = PortDetector.merge(
            logPort: portTrackers[id]?.logPort,
            lsofPorts: lastLsofPorts[id] ?? [],
            consecutiveEmptyLsof: consecutiveEmptyLsof[id] ?? 0
        )
        runtimes[id] = r
    }

    private func cancelPortPolling(_ id: UUID) {
        portPollTasks[id]?.cancel()
        portPollTasks[id] = nil
        consecutiveEmptyLsof[id] = nil
        lastLsofPorts[id] = nil
    }

    private func removeConfig(_ id: UUID) {
        cancelPortPolling(id)
        configs.removeAll { $0.id == id }
        runtimes[id] = nil
        logs.remove(id: id)
        portTrackers[id] = nil
    }

    private func persist() {
        let writable = configs.filter { runtimes[$0.id]?.removedFromConfig != true }
        try? store.save(writable)
    }
}
