import XCTest
@testable import BarCmd

@MainActor
final class AppModelTests: XCTestCase {
    private var scratchDirs: [URL] = []

    override func tearDown() {
        for dir in scratchDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        scratchDirs = []
        super.tearDown()
    }

    func testStartTransitionsStoppedToStartingToRunning() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, processes, _, _) = try makeHarness(configs: [config])
        XCTAssertEqual(model.runtime(id).status, .stopped)

        var sawStarting = false
        processes.onStart = {
            XCTAssertEqual(model.runtime(id).status, .starting)
            sawStarting = true
        }

        await model.start(id)
        XCTAssertTrue(sawStarting)
        XCTAssertEqual(model.runtime(id).status, .running)
        XCTAssertEqual(model.runtime(id).pid, 4242)
        XCTAssertNotNil(model.runtime(id).startedAt)
    }

    func testNaturalExitKeepsExitCodeAndClearsPidPort() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, processes, _, _) = try makeHarness(configs: [config])
        await model.start(id)
        processes.finish(id: id, code: 3)
        await waitUntil { model.runtime(id).status == .exited }
        XCTAssertEqual(model.runtime(id).status, .exited)
        XCTAssertEqual(model.runtime(id).exitCode, 3)
        XCTAssertNil(model.runtime(id).pid)
        XCTAssertNil(model.runtime(id).port)
    }

    func testStopClearsPidPortExitCodeStartedAt() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, processes, _, _) = try makeHarness(configs: [config])
        await model.start(id)
        XCTAssertNotNil(model.runtime(id).startedAt)
        await model.stop(id)
        await waitUntil { model.runtime(id).status == .stopped }
        XCTAssertEqual(model.runtime(id).status, .stopped)
        XCTAssertNil(model.runtime(id).pid)
        XCTAssertNil(model.runtime(id).port)
        XCTAssertNil(model.runtime(id).exitCode)
        XCTAssertNil(model.runtime(id).startedAt)
        XCTAssertEqual(processes.stoppedIDs, [id])
    }

    func testStartWhileRunningDoesNotCallProcessAgain() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, processes, _, _) = try makeHarness(configs: [config])
        await model.start(id)
        XCTAssertEqual(processes.startCount, 1)
        await model.start(id)
        XCTAssertEqual(processes.startCount, 1)
        XCTAssertEqual(model.runtime(id).status, .running)
    }

    func testMissingCwdExitsWithChineseLogAndDoesNotStart() async throws {
        let id = UUID()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("barcmd-missing-\(UUID().uuidString)", isDirectory: true)
        let config = CommandConfig(id: id, name: "web", command: "echo ok", cwd: missing.path)
        let (model, _, processes, logs, _) = try makeHarness(configs: [config])
        await model.start(id)
        XCTAssertEqual(model.runtime(id).status, .exited)
        XCTAssertEqual(processes.startCount, 0)
        let joined = logs.lines(id: id).joined()
        XCTAssertTrue(joined.contains("工作目录不存在："), "log was \(joined)")
    }

    func testRequestEditRunningPrompterFalseStaysRunning() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let prompter = FakePrompter()
        prompter.confirmStopForEditResult = false
        let (model, _, processes, _, _) = try makeHarness(configs: [config], prompter: prompter)
        await model.start(id)
        let opened = await model.requestEdit(id)
        XCTAssertFalse(opened)
        XCTAssertNil(model.pendingEdit)
        XCTAssertEqual(model.runtime(id).status, .running)
        XCTAssertTrue(processes.stoppedIDs.isEmpty)
    }

    func testRequestEditRunningPrompterTrueStops() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let prompter = FakePrompter()
        prompter.confirmStopForEditResult = true
        let (model, _, processes, _, _) = try makeHarness(configs: [config], prompter: prompter)
        await model.start(id)
        let opened = await model.requestEdit(id)
        XCTAssertTrue(opened)
        XCTAssertEqual(model.pendingEdit?.id, id)
        XCTAssertEqual(processes.stoppedIDs, [id])
        await waitUntil { model.runtime(id).status == .stopped }
        XCTAssertEqual(model.runtime(id).status, .stopped)
    }

    func testRequestDeleteStoppedConfirmTrueRemovesAndSaves() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let prompter = FakePrompter()
        prompter.confirmDeleteResult = true
        let (model, store, _, _, _) = try makeHarness(configs: [config], prompter: prompter)
        XCTAssertEqual(model.runtime(id).status, .stopped)
        let deleted = await model.requestDelete(id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.configs.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testApplyExternalReloadKeepsRunningRemovedUntilStop() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, store, _, _, _) = try makeHarness(configs: [config])
        await model.start(id)
        try store.save([])
        try model.applyExternalReload()
        XCTAssertEqual(model.configs.map(\.id), [id])
        XCTAssertTrue(model.runtime(id).removedFromConfig)
        XCTAssertEqual(model.runtime(id).status, .running)
        await model.stop(id)
        await waitUntil { model.configs.isEmpty }
        XCTAssertTrue(model.configs.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testRunningCountIsOneWhenRunning() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(configs: [config])
        XCTAssertEqual(model.runningCount, 0)
        await model.start(id)
        XCTAssertEqual(model.runningCount, 1)
    }

    func testPollSetsPortFromLsof() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(
            configs: [config],
            lsof: FakeLsofClient(ports: [5173])
        )
        await model.start(id)
        await model.pollPortsOnce(id: id)
        XCTAssertEqual(model.runtime(id).port, 5173)
    }

    func testBeginWatchingIgnoresExternalChangeWhileQuitting() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let prompter = FakePrompter()
        let (model, store, _, _, _) = try makeHarness(configs: [config], prompter: prompter)
        model.beginWatching()
        model.isQuitting = true

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

        try await Task.sleep(nanoseconds: 1_000_000_000)
        store.stopWatching()
        XCTAssertEqual(prompter.confirmReloadCallCount, 0)
    }

    func testBeginWatchingReloadErrorAlerts() async throws {
        let config = CommandConfig(id: UUID(), name: "web", command: "echo ok")
        let prompter = FakePrompter()
        let (model, store, _, _, _) = try makeHarness(configs: [config], prompter: prompter)
        model.beginWatching()

        try "::::".write(to: store.fileURL, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(1.5)
        while prompter.alerts.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        store.stopWatching()
        XCTAssertFalse(prompter.alerts.isEmpty, "reload error should alert instead of dying in Task")
        XCTAssertEqual(prompter.alerts.first?.title, "配置加载失败")
        XCTAssertNotNil(model.loadError)
    }

    func testLogLineWithoutPortDoesNotClearLsofMergedPort() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, processes, logs, _) = try makeHarness(
            configs: [config],
            lsof: FakeLsofClient(ports: [5173])
        )
        await model.start(id)
        await model.pollPortsOnce(id: id)
        XCTAssertEqual(model.runtime(id).port, 5173)

        processes.emit(id: id, line: "compiling module")
        await waitUntil { logs.lines(id: id).contains(where: { $0.contains("compiling module") }) }
        XCTAssertEqual(model.runtime(id).port, 5173)
    }

    private func makeHarness(
        configs: [CommandConfig],
        prompter: FakePrompter = FakePrompter(),
        lsof: LsofClient = FakeLsofClient()
    ) throws -> (AppModel, ConfigStore, FakeProcess, LogBufferStore, FakePrompter) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("barcmd-appmodel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)
        let store = ConfigStore(directory: dir)
        try store.save(configs)
        let processes = FakeProcess()
        let logs = LogBufferStore()
        let model = AppModel(
            store: store,
            processes: processes,
            logs: logs,
            prompter: prompter,
            lsof: lsof
        )
        return (model, store, processes, logs, prompter)
    }

    private func waitUntil(timeout: TimeInterval = 1, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
