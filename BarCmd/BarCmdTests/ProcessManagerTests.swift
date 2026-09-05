import XCTest
@testable import BarCmd

final class ProcessManagerTests: XCTestCase {
    func testEchoExitCode() async throws {
        let mgr = ProcessManager()
        let id = UUID()
        let config = CommandConfig(id: id, name: "e", command: "echo hi >&2; echo ok; exit 3")
        let cwd = URL(fileURLWithPath: NSHomeDirectory())
        let lines = Locked<[String]>([])
        let exited = expectation(description: "exit")
        var code: Int32 = 0
        try await mgr.start(config: config, cwd: cwd, onOutput: { _, line in
            lines.value.append(line)
        }, onExit: { _, c in
            code = c
            exited.fulfill()
        })
        await fulfillment(of: [exited], timeout: 10)
        XCTAssertEqual(code, 3)
        let joined = lines.value.joined(separator: "\n")
        XCTAssertTrue(joined.contains("ok"))
        XCTAssertTrue(joined.contains("hi"))
    }

    func testStopSleep() async throws {
        let mgr = ProcessManager()
        let id = UUID()
        let config = CommandConfig(id: id, name: "s", command: "sleep 30")
        let exited = expectation(description: "stopped")
        try await mgr.start(config: config, cwd: URL(fileURLWithPath: NSHomeDirectory()), onOutput: { _, _ in }, onExit: { _, _ in
            exited.fulfill()
        })
        let snap = await mgr.runtimeSnapshot(id: id)
        XCTAssertNotNil(snap?.pid)
        await mgr.stop(id: id)
        await fulfillment(of: [exited], timeout: 8)
        let after = await mgr.runtimeSnapshot(id: id)
        XCTAssertNil(after)
    }

    func testStopThenImmediateStartDoesNotKillSecondProcess() async throws {
        let mgr = ProcessManager()
        let id = UUID()
        let config = CommandConfig(id: id, name: "s", command: "sleep 30")
        let cwd = URL(fileURLWithPath: NSHomeDirectory())
        let firstExits = Locked(0)
        let secondExits = Locked(0)
        let secondShouldStay = expectation(description: "second process stays up")
        secondShouldStay.isInverted = true

        try await mgr.start(config: config, cwd: cwd, onOutput: { _, _ in }, onExit: { _, _ in
            firstExits.value += 1
        })
        let firstPID = await mgr.runtimeSnapshot(id: id)?.pid
        XCTAssertNotNil(firstPID)

        await mgr.stop(id: id)
        let afterStop = await mgr.runtimeSnapshot(id: id)
        XCTAssertNil(afterStop, "stop must finish teardown before returning")

        try await mgr.start(config: config, cwd: cwd, onOutput: { _, _ in }, onExit: { _, _ in
            secondExits.value += 1
            secondShouldStay.fulfill()
        })
        let secondPID = await mgr.runtimeSnapshot(id: id)?.pid
        XCTAssertNotNil(secondPID, "second start must actually spawn")
        XCTAssertNotEqual(secondPID, firstPID)

        await fulfillment(of: [secondShouldStay], timeout: 1.0)
        XCTAssertEqual(secondExits.value, 0)
        let stillSecond = await mgr.runtimeSnapshot(id: id)?.pid
        XCTAssertEqual(stillSecond, secondPID)

        await mgr.stop(id: id)
        XCTAssertEqual(firstExits.value, 1)
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    init(_ value: T) { storage = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
