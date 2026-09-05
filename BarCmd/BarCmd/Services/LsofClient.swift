import Foundation

protocol LsofClient: Sendable {
    func listeningPorts(pids: [Int32]) throws -> [Int]
}

enum LsofCommand {
    static func arguments(pids: [Int32]) -> [String]? {
        guard !pids.isEmpty else { return nil }
        return ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", pids.map(String.init).joined(separator: ",")]
    }
}

struct RealLsofClient: LsofClient {
    func listeningPorts(pids: [Int32]) throws -> [Int] {
        guard let arguments = LsofCommand.arguments(pids: pids) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return LsofParser.ports(fromStandardOutput: output)
    }
}
