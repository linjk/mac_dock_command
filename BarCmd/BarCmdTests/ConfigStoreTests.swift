import XCTest
import Yams
@testable import BarCmd

final class ConfigStoreTests: XCTestCase {
    var dir: URL!
    var store: ConfigStore!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ConfigStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsEmptyAndWritesSkeleton() throws {
        let list = try store.load()
        XCTAssertTrue(list.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testRoundTrip() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let config = CommandConfig(id: id, name: "DSH", command: "npx dsh web", cwd: "~", env: ["FOO": "bar"])
        try store.save([config])
        let loaded = try store.load()
        XCTAssertEqual(loaded, [config])
        XCTAssertNotNil(store.lastWrittenHash)
        XCTAssertEqual(store.lastWrittenHash, try store.currentFileHash())
    }

    func testUnknownFieldsIgnored() throws {
        let yaml = """
        commands:
          - id: "22222222-2222-2222-2222-222222222222"
            name: "X"
            command: "echo"
            autoStart: true
        """
        try yaml.write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = try store.load()
        XCTAssertEqual(loaded.first?.name, "X")
        XCTAssertEqual(loaded.first?.env, [:])
    }

    func testInvalidYAMLThrows() throws {
        try "::::".write(to: store.fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }

    func testSaveWritesBackup() throws {
        let config = CommandConfig(id: UUID(), name: "A", command: "true")
        try store.save([config])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))
    }
}
