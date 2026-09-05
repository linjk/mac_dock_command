import Darwin
import Foundation

enum ProcessSpawner {
    static func shellExecutable() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"]
        if let shell, !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    static func arguments(command: String, env: [String: String], shellName: String) -> [String] {
        let exports = posixExports(env)
        let script: String
        switch shellName {
        case "zsh":
            script = "source \"${ZDOTDIR:-$HOME}/.zshrc\" >/dev/null 2>&1 || true; \(exports)\(command)"
        case "bash":
            script = "source \"$HOME/.bashrc\" >/dev/null 2>&1 || true; \(exports)\(command)"
        default:
            script = "\(exports)\(command)"
        }
        return ["-l", "-c", script]
    }

    static func posixExports(_ env: [String: String]) -> String {
        env.compactMap { key, value -> String? in
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                return nil
            }
            return "export \(key)=\"\(posixEscape(value))\"; "
        }.joined()
    }

    static func launch(
        command: String,
        env: [String: String],
        cwd: URL,
        configure: ((Process) -> Void)? = nil
    ) throws -> (process: Process, pid: Int32, pgid: Int32) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileNoSuchFileError,
                userInfo: [NSFilePathErrorKey: cwd.path]
            )
        }

        let shell = shellExecutable()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments(command: command, env: env, shellName: shellName)
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        configure?(process)
        try process.run()

        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 {
            return (process, pid, pid)
        }
        let current = getpgid(pid)
        return (process, pid, current >= 0 ? current : pid)
    }

    private static func posixEscape(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\", "\"", "$", "`":
                escaped.append("\\")
                escaped.append(character)
            default:
                escaped.append(character)
            }
        }
        return escaped
    }
}
