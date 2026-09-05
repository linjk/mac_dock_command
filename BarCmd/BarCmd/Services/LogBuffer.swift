import Foundation

final class LogBufferStore: @unchecked Sendable {
    static let capacity = 10_000
    private let lock = NSLock()
    private var storage: [UUID: [String]] = [:]
    private var continuations: [UUID: [UUID: AsyncStream<[String]>.Continuation]] = [:]

    func append(id: UUID, line: String) {
        let cleaned = ANSIStripper.strip(line)
        lock.lock()
        var lines = storage[id] ?? []
        lines.append(cleaned)
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
        storage[id] = lines
        let snapshot = lines
        let conts = continuations[id]?.values
        lock.unlock()
        conts?.forEach { $0.yield(snapshot) }
    }

    func lines(id: UUID) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return storage[id] ?? []
    }

    func clear(id: UUID) {
        lock.lock()
        storage[id] = []
        let conts = continuations[id]?.values
        lock.unlock()
        conts?.forEach { $0.yield([]) }
    }

    func remove(id: UUID) {
        lock.lock()
        storage[id] = nil
        let conts = continuations[id]?.values
        continuations[id] = nil
        lock.unlock()
        conts?.forEach { $0.finish() }
    }

    func updates(id: UUID) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let token = UUID()
            lock.lock()
            var bag = continuations[id] ?? [:]
            bag[token] = continuation
            continuations[id] = bag
            let initial = storage[id] ?? []
            lock.unlock()
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id]?[token] = nil
                self.lock.unlock()
            }
        }
    }
}
