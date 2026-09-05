protocol LsofClient: Sendable {
    func listeningPorts(pids: [Int32]) throws -> [Int]
}
