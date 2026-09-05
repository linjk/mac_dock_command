import Darwin
import Foundation

actor ProcessManager: ProcessControlling {
    private struct Runtime {
        let process: Process
        let pid: Int32
        let pgid: Int32
        var stopRequested: Bool
    }

    private final class LineAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var leftover = ""

        func lines(from data: Data, flush: Bool = false) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            if !data.isEmpty {
                leftover += String(decoding: data, as: UTF8.self)
            }
            var result: [String] = []
            while let range = leftover.range(of: "\n") {
                let line = String(leftover[..<range.lowerBound])
                leftover.removeSubrange(..<range.upperBound)
                result.append(ANSIStripper.strip(line))
            }
            if flush, !leftover.isEmpty {
                result.append(ANSIStripper.strip(leftover))
                leftover = ""
            }
            return result
        }
    }

    private var runtimes: [UUID: Runtime] = [:]
    private var pendingExits: [UUID: Int32] = [:]

    func start(
        config: CommandConfig,
        cwd: URL,
        onOutput: @escaping @Sendable (UUID, String) -> Void,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) async throws {
        if runtimes[config.id] != nil {
            return
        }

        let id = config.id
        let accumulator = LineAccumulator()
        let (process, pid, pgid) = try ProcessSpawner.launch(
            command: config.command,
            env: config.env,
            cwd: cwd
        ) { process in
            if let pipe = process.standardOutput as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    for line in accumulator.lines(from: data) {
                        onOutput(id, line)
                    }
                }
            }
            process.terminationHandler = { proc in
                if let pipe = proc.standardOutput as? Pipe {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let rest = pipe.fileHandleForReading.availableData
                    for line in accumulator.lines(from: rest, flush: true) {
                        onOutput(id, line)
                    }
                }
                let code = proc.terminationStatus
                Task {
                    await self.didTerminate(id: id, code: code, onExit: onExit)
                }
            }
        }

        if let code = pendingExits.removeValue(forKey: id) {
            onExit(id, code)
            return
        }
        runtimes[id] = Runtime(process: process, pid: pid, pgid: pgid, stopRequested: false)
    }

    func stop(id: UUID) async {
        guard var runtime = runtimes[id] else { return }
        runtime.stopRequested = true
        runtimes[id] = runtime

        signal(runtime, SIGTERM)
        await waitWhileRunning(runtime.process, seconds: 5)
        if runtime.process.isRunning {
            signal(runtime, SIGKILL)
            await waitWhileRunning(runtime.process, seconds: 2)
        }
    }

    func stopAll() async {
        let ids = Array(runtimes.keys)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    await self.stop(id: id)
                }
            }
        }
    }

    func runtimeSnapshot(id: UUID) async -> (pid: Int32, pgid: Int32)? {
        guard let runtime = runtimes[id] else { return nil }
        return (runtime.pid, runtime.pgid)
    }

    private func didTerminate(
        id: UUID,
        code: Int32,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) {
        if runtimes.removeValue(forKey: id) != nil {
            onExit(id, code)
        } else {
            pendingExits[id] = code
        }
    }

    private func signal(_ runtime: Runtime, _ signal: Int32) {
        if runtime.pgid == runtime.pid {
            _ = ProcessTree.send(signal, toGroup: runtime.pgid)
        } else {
            ProcessTree.send(signal, toPIDs: ProcessTree.descendantPIDs(of: runtime.pid))
        }
    }

    private func waitWhileRunning(_ process: Process, seconds: Double) async {
        let limit = UInt64(seconds * 1_000_000_000)
        let started = DispatchTime.now().uptimeNanoseconds
        while process.isRunning {
            if DispatchTime.now().uptimeNanoseconds &- started >= limit {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
