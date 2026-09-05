import Foundation

enum PortDetector {
    private static let patterns: [(priority: Int, pattern: String)] = [
        (0, #"https?://(?:127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\]):(\d+)"#),
        (1, #"(?i)listening on(?: port)? (\d+)"#),
        (2, #"(?i)Local:\s+https?://\S+:(\d+)"#),
        (3, #"(?i)server running (?:on|at).*:(\d+)"#),
    ]

    static func parseLogLine(_ line: String) -> (priority: Int, port: Int)? {
        // Phrase patterns first so Vite "Local:" is not classified as a generic URL.
        for item in [patterns[1], patterns[2], patterns[3], patterns[0]] {
            if let port = firstPort(in: line, pattern: item.pattern) {
                return (item.priority, port)
            }
        }
        return nil
    }

    static func merge(logPort: Int?, lsofPorts: [Int], consecutiveEmptyLsof: Int) -> Int? {
        if !lsofPorts.isEmpty {
            if let logPort, lsofPorts.contains(logPort) {
                return logPort
            }
            if let userMin = lsofPorts.filter({ $0 >= 1024 }).min() {
                return userMin
            }
            return lsofPorts.min()
        }
        if logPort == nil && consecutiveEmptyLsof >= 3 {
            return nil
        }
        return logPort
    }

    private static func firstPort(in line: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              match.numberOfRanges >= 2,
              let portRange = Range(match.range(at: 1), in: line),
              let port = Int(line[portRange]),
              (1...65535).contains(port)
        else {
            return nil
        }
        return port
    }
}

struct PortTracker {
    var logPort: Int?
    var logPriority: Int = .max

    mutating func ingestLogLine(_ line: String) -> Int? {
        guard let hit = PortDetector.parseLogLine(line) else {
            return logPort
        }
        if logPort == nil || hit.priority < logPriority {
            logPort = hit.port
            logPriority = hit.priority
        }
        return logPort
    }
}

enum LsofParser {
    static func ports(fromStandardOutput output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+) \(LISTEN\)"#) else {
            return []
        }
        let nsRange = NSRange(output.startIndex..., in: output)
        return regex.matches(in: output, range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let portRange = Range(match.range(at: 1), in: output),
                  let port = Int(output[portRange]),
                  (1...65535).contains(port)
            else {
                return nil
            }
            return port
        }
    }
}
