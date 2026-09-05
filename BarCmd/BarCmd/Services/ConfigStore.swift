import AppKit
import CryptoKit
import Foundation
import Yams

struct CommandsFile: Codable {
    var commands: [CommandConfig]
}

struct ConfigError: Error, LocalizedError {
    var line: Int?
    var message: String
    var errorDescription: String? {
        if let line {
            return "第 \(line) 行：\(message)"
        }
        return message
    }
}

final class ConfigStore {
    let directory: URL
    let fileURL: URL
    let backupURL: URL
    private(set) var lastWrittenHash: String?

    init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("commands.yaml")
        self.backupURL = directory.appendingPathComponent("commands.yaml.bak")
    }

    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directory: root.appendingPathComponent("BarCmd", isDirectory: true))
    }

    func load() throws -> [CommandConfig] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try save([])
            return []
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            let file = try YAMLDecoder().decode(CommandsFile.self, from: text)
            return file.commands
        } catch {
            let line = (error as? YamlError).flatMap { _ in nil as Int? }
            throw ConfigError(line: line, message: error.localizedDescription)
        }
    }

    func save(_ configs: [CommandConfig]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = try YAMLEncoder().encode(CommandsFile(commands: configs))
        let temp = directory.appendingPathComponent("commands.yaml.tmp")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.replaceItem(at: fileURL, withItemAt: temp, backupItemName: nil, options: [], resultingItemURL: nil)
        } else {
            try FileManager.default.moveItem(at: temp, to: fileURL)
        }
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        lastWrittenHash = try currentFileHash()
    }

    func currentFileHash() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
