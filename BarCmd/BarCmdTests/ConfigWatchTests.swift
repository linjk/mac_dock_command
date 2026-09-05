import XCTest
@testable import BarCmd

final class ConfigWatchTests: XCTestCase {
    var dir: URL!
    var store: ConfigStore!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ConfigStore(directory: dir)
    }

    override func tearDown() {
        store.stopWatching()
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveDoesNotFireExternalChange() throws {
        let config = CommandConfig(id: UUID(), name: "A", command: "true")
        try store.save([config])

        let unexpected = expectation(description: "save should not fire")
        unexpected.isInverted = true
        store.startWatching {
            unexpected.fulfill()
        }

        try store.save([config])
        wait(for: [unexpected], timeout: 1.0)
    }

    func testExternalRewriteFiresAfterDebounce() throws {
        let config = CommandConfig(id: UUID(), name: "A", command: "true")
        try store.save([config])

        let fired = expectation(description: "external rewrite fires")
        store.startWatching {
            fired.fulfill()
        }

        let yaml = """
        commands:
          - id: "33333333-3333-3333-3333-333333333333"
            name: "B"
            command: "echo"
        """
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(yaml.utf8))
        try handle.close()

        wait(for: [fired], timeout: 1.5)
    }

    func testLoadBaselinesLastWrittenHash() throws {
        try writeExistingYAML()
        _ = try store.load()
        XCTAssertEqual(store.lastWrittenHash, try store.currentFileHash())
    }

    func testDirectoryEventWithoutContentChangeDoesNotFire() throws {
        try writeExistingYAML()
        _ = try store.load()

        let unexpected = expectation(description: "hash-unchanged directory event should not fire")
        unexpected.isInverted = true
        store.startWatching {
            unexpected.fulfill()
        }

        let sibling = dir.appendingPathComponent("unrelated.txt")
        try "x".write(to: sibling, atomically: true, encoding: .utf8)
        wait(for: [unexpected], timeout: 1.0)
    }

    private func writeExistingYAML() throws {
        let yaml = """
        commands:
          - id: "33333333-3333-3333-3333-333333333333"
            name: "B"
            command: "echo"
        """
        try yaml.write(to: store.fileURL, atomically: true, encoding: .utf8)
    }
}
