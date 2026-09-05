import Foundation
@testable import BarCmd

final class FakeProcess: ProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [UUID: Int32] = [:]
    private var onExits: [UUID: @Sendable (UUID, Int32) -> Void] = [:]
    private var onOutputs: [UUID: @Sendable (UUID, String) -> Void] = [:]

    private(set) var startCount = 0
    private(set) var startedIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    var nextPID: Int32 = 4242
    var onStart: (@MainActor () -> Void)?

    func start(
        config: CommandConfig,
        cwd: URL,
        onOutput: @escaping @Sendable (UUID, String) -> Void,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) async throws {
        lock.lock()
        startCount += 1
        startedIDs.append(config.id)
        let pid = nextPID
        nextPID += 1
        pids[config.id] = pid
        onOutputs[config.id] = onOutput
        onExits[config.id] = onExit
        lock.unlock()
        if let onStart {
            await MainActor.run { onStart() }
        }
    }

    func stop(id: UUID) async {
        lock.lock()
        stoppedIDs.append(id)
        lock.unlock()
        finish(id: id, code: 0)
    }

    func stopAll() async {
        lock.lock()
        let ids = Array(pids.keys)
        lock.unlock()
        for id in ids {
            await stop(id: id)
        }
    }

    func runtimeSnapshot(id: UUID) async -> (pid: Int32, pgid: Int32)? {
        lock.lock()
        defer { lock.unlock() }
        guard let pid = pids[id] else { return nil }
        return (pid, pid)
    }

    func finish(id: UUID, code: Int32) {
        lock.lock()
        let handler = onExits[id]
        pids[id] = nil
        lock.unlock()
        handler?(id, code)
    }

    func emit(id: UUID, line: String) {
        lock.lock()
        let handler = onOutputs[id]
        lock.unlock()
        handler?(id, line)
    }
}

struct FakeLsofClient: LsofClient {
    var ports: [Int] = []

    func listeningPorts(pids: [Int32]) throws -> [Int] { ports }
}

final class FakePrompter: UserPrompter {
    var confirmStopForEditResult = true
    var confirmStopForDeleteResult = true
    var confirmDeleteResult = true
    var confirmQuitResult = true
    var confirmReloadResult = true
    private(set) var confirmReloadCallCount = 0
    private(set) var alerts: [(title: String, message: String)] = []

    func confirmStopForEdit(name: String) async -> Bool { confirmStopForEditResult }
    func confirmStopForDelete(name: String) async -> Bool { confirmStopForDeleteResult }
    func confirmDelete(name: String) async -> Bool { confirmDeleteResult }
    func confirmQuit(runningCount: Int) async -> Bool { confirmQuitResult }
    func confirmReload() async -> Bool {
        confirmReloadCallCount += 1
        return confirmReloadResult
    }
    func alert(title: String, message: String) async {
        alerts.append((title, message))
    }
}
