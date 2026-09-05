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

    func testPresentEditorSetsPendingAndOpensWindow() throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(configs: [config])
        var opened: UUID?
        model.openEditWindow = { opened = $0 }

        model.presentEditor(config)

        XCTAssertEqual(model.pendingEdit?.id, id)
        XCTAssertEqual(opened, id)
    }

    func testRequestEditOpensEditWindow() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(configs: [config])
        var opened: UUID?
        model.openEditWindow = { opened = $0 }

        let ok = await model.requestEdit(id)

        XCTAssertTrue(ok)
        XCTAssertEqual(model.pendingEdit?.id, id)
        XCTAssertEqual(opened, id)
    }

    func testDismissEditorClearsPendingEdit() throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(configs: [config])
        model.presentEditor(config)

        model.dismissEditor(id: id)

        XCTAssertNil(model.pendingEdit)
    }

    func testDismissEditorIgnoresOtherID() throws {
        let id = UUID()
        let other = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let (model, _, _, _, _) = try makeHarness(configs: [config])
        model.presentEditor(config)

        model.dismissEditor(id: other)

        XCTAssertEqual(model.pendingEdit?.id, id)
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

    func testApplyExternalReloadPicksUpCommandWrittenToDisk() throws {
        let echo = CommandConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "echo-test",
            command: "echo hello-barcmd; sleep 8"
        )
        let dsh = CommandConfig(
            id: UUID(uuidString: "8E0094E8-B169-40A8-80AD-566B66967712")!,
            name: "DSH",
            command: "npx @deepseek-ai/dsh web"
        )
        let (model, store, _, _, _) = try makeHarness(configs: [echo])
        try store.save([echo, dsh])
        try model.applyExternalReload()
        XCTAssertEqual(model.configs.map(\.name), ["echo-test", "DSH"])
        XCTAssertEqual(model.configs.map(\.id), [echo.id, dsh.id])
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

    func testRestartClearsStalePortFromPreviousRun() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let lsof = FakeLsofClient(ports: [5173])
        let (model, _, processes, logs, _) = try makeHarness(configs: [config], lsof: lsof)

        await model.start(id)
        processes.emit(id: id, line: "  ➜  Local:   http://localhost:5173/")
        await waitUntil { logs.lines(id: id).contains(where: { $0.contains("5173") }) }
        await model.pollPortsOnce(id: id)
        XCTAssertEqual(model.runtime(id).port, 5173)

        await model.stop(id)
        await waitUntil { model.runtime(id).status == .stopped }
        XCTAssertNil(model.runtime(id).port)

        lsof.ports = []
        await model.start(id)
        XCTAssertEqual(model.runtime(id).status, .running)
        XCTAssertNil(model.runtime(id).port, "restart must not keep the previous port")

        processes.emit(id: id, line: "compiling module")
        await waitUntil { logs.lines(id: id).contains(where: { $0.contains("compiling module") }) }
        await model.pollPortsOnce(id: id)
        XCTAssertNil(model.runtime(id).port, "stale PortTracker must not restore 5173")

        lsof.ports = [5174]
        processes.emit(id: id, line: "  ➜  Local:   http://localhost:5174/")
        await waitUntil { logs.lines(id: id).contains(where: { $0.contains("5174") }) }
        await model.pollPortsOnce(id: id)
        XCTAssertEqual(model.runtime(id).port, 5174)
    }

    func testPersistSaveFailureAlerts() async throws {
        let id = UUID()
        let config = CommandConfig(id: id, name: "web", command: "echo ok")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("barcmd-appmodel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)

        let store = FailingSaveStore(directory: dir)
        try store.save([config])
        store.failSave = true

        let prompter = FakePrompter()
        let model = AppModel(
            store: store,
            processes: FakeProcess(),
            logs: LogBufferStore(),
            prompter: prompter,
            lsof: FakeLsofClient()
        )

        await model.add(CommandConfig(id: UUID(), name: "other", command: "echo"))
        await waitUntil { !prompter.alerts.isEmpty }
        XCTAssertEqual(prompter.alerts.first?.title, "保存配置失败")
        XCTAssertTrue(
            prompter.alerts.first?.message.contains("保存配置失败") == true,
            "alert message was \(prompter.alerts.first?.message ?? "nil")"
        )
        XCTAssertTrue(prompter.alerts.first?.message.contains("disk full") == true)
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
