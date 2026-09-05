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
    private var pendingExits: [Int32: Int32] = [:]
    private var teardownWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

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
                let terminatedPID = proc.processIdentifier
                Task {
                    await self.didTerminate(id: id, pid: terminatedPID, code: code, onExit: onExit)
                }
            }
        }

        if let code = pendingExits.removeValue(forKey: pid) {
            onExit(id, code)
            return
        }
        runtimes[id] = Runtime(process: process, pid: pid, pgid: pgid, stopRequested: false)
    }

    func stop(id: UUID) async {
        guard var runtime = runtimes[id] else { return }
        let pid = runtime.pid
        runtime.stopRequested = true
        runtimes[id] = runtime

        signal(runtime, SIGTERM)
        await waitWhileRunning(runtime.process, seconds: 5)
        if runtime.process.isRunning {
            signal(runtime, SIGKILL)
            await waitWhileRunning(runtime.process, seconds: 2)
        }
        await waitForTeardown(id: id, pid: pid)
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
        pid: Int32,
        code: Int32,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) {
        if let current = runtimes[id], current.pid == pid {
            runtimes.removeValue(forKey: id)
            onExit(id, code)
            resumeTeardownWaiters(id: id)
            return
        }
        if runtimes[id] == nil {
            pendingExits[pid] = code
        }
    }

    private func waitForTeardown(id: UUID, pid: Int32) async {
        if runtimes[id]?.pid != pid {
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.suspendUntilTeardown(id: id, pid: pid)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.timeoutTeardown(id: id, pid: pid)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func suspendUntilTeardown(id: UUID, pid: Int32) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if runtimes[id]?.pid != pid {
                continuation.resume()
                return
            }
            teardownWaiters[id, default: []].append(continuation)
        }
    }

    private func timeoutTeardown(id: UUID, pid: Int32) {
        guard runtimes[id]?.pid == pid else { return }
        runtimes.removeValue(forKey: id)
        resumeTeardownWaiters(id: id)
    }

    private func resumeTeardownWaiters(id: UUID) {
        let waiters = teardownWaiters.removeValue(forKey: id) ?? []
        for waiter in waiters {
            waiter.resume()
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
