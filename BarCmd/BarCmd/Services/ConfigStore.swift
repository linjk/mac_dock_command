import AppKit
import CryptoKit
import Darwin
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
    private var watchSource: DispatchSourceFileSystemObject?
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var watchDebounce: DispatchWorkItem?
    private var onExternalChange: (() -> Void)?

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

    func loadBackup() throws -> [CommandConfig] {
        let text = try String(contentsOf: backupURL, encoding: .utf8)
        do {
            let file = try YAMLDecoder().decode(CommandsFile.self, from: text)
            return file.commands
        } catch {
            throw ConfigError(line: nil, message: error.localizedDescription)
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

    func startWatching(onExternalChange: @escaping () -> Void) {
        stopWatching()
        self.onExternalChange = onExternalChange

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        watchSource = makeFileSystemSource(
            path: directory.path,
            eventMask: [.write, .rename, .delete]
        ) { [weak self] in
            self?.armFileWatch()
            self?.scheduleDebouncedCheck()
        }
        armFileWatch()
    }

    func stopWatching() {
        watchDebounce?.cancel()
        watchDebounce = nil
        watchSource?.cancel()
        watchSource = nil
        fileWatchSource?.cancel()
        fileWatchSource = nil
        onExternalChange = nil
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    deinit {
        stopWatching()
    }

    private func armFileWatch() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        fileWatchSource = makeFileSystemSource(
            path: fileURL.path,
            eventMask: [.write, .rename, .delete, .extend]
        ) { [weak self] in
            self?.scheduleDebouncedCheck()
        }
    }

    private func makeFileSystemSource(
        path: String,
        eventMask: DispatchSource.FileSystemEvent,
        handler: @escaping () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: eventMask,
            queue: .main
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        return source
    }

    private func scheduleDebouncedCheck() {
        watchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let current = try? self.currentFileHash(),
                  current != self.lastWrittenHash else { return }
            self.onExternalChange?()
        }
        watchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
