import Foundation

struct CommandRuntime: Equatable, Sendable {
    var status: CommandStatus = .stopped
    var pid: Int32?
    var pgid: Int32?
    var port: Int?
    var exitCode: Int32?
    var startedAt: Date?
    var removedFromConfig: Bool = false
}
