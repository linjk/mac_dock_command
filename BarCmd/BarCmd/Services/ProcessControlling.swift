import Foundation

protocol ProcessControlling: Sendable {
    func start(
        config: CommandConfig,
        cwd: URL,
        onOutput: @escaping @Sendable (UUID, String) -> Void,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) async throws
    func stop(id: UUID) async
    func stopAll() async
    func runtimeSnapshot(id: UUID) async -> (pid: Int32, pgid: Int32)?
}
