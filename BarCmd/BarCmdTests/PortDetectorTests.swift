import XCTest
@testable import BarCmd

final class PortDetectorTests: XCTestCase {
    func testURL127() {
        let hit = PortDetector.parseLogLine("ready at http://127.0.0.1:3080")
        XCTAssertEqual(hit?.port, 3080)
        XCTAssertEqual(hit?.priority, 0)
    }

    func testLocalhostHTTPS() {
        XCTAssertEqual(PortDetector.parseLogLine("https://localhost:5173")?.port, 5173)
    }

    func testListeningOn() {
        XCTAssertEqual(PortDetector.parseLogLine("Listening on port 4000")?.port, 4000)
        XCTAssertEqual(PortDetector.parseLogLine("listening on 4000")?.priority, 1)
    }

    func testViteLocal() {
        XCTAssertEqual(PortDetector.parseLogLine("  ➜  Local:   http://localhost:5173/")?.port, 5173)
        XCTAssertEqual(PortDetector.parseLogLine("  ➜  Local:   http://localhost:5173/")?.priority, 2)
    }

    func testServerRunning() {
        XCTAssertEqual(PortDetector.parseLogLine("Server running on 0.0.0.0:8080")?.port, 8080)
    }

    func testRejectsTimeAndVersion() {
        XCTAssertNil(PortDetector.parseLogLine("12:34:56"))
        XCTAssertNil(PortDetector.parseLogLine("version v1.2.3"))
    }

    func testHigherPriorityOverrides() {
        var tracker = PortTracker()
        XCTAssertEqual(tracker.ingestLogLine("listening on 4000"), 4000)
        XCTAssertEqual(tracker.ingestLogLine("http://127.0.0.1:3080"), 3080)
        XCTAssertEqual(tracker.ingestLogLine("listening on 9000"), 3080)
    }

    func testMergePrefersLsofIntersection() {
        XCTAssertEqual(PortDetector.merge(logPort: 5173, lsofPorts: [5173, 24678], consecutiveEmptyLsof: 0), 5173)
    }

    func testMergeMinUserPort() {
        XCTAssertEqual(PortDetector.merge(logPort: 80, lsofPorts: [24678, 5173], consecutiveEmptyLsof: 0), 5173)
    }

    func testMergeEmptyKeepsLogUntilThree() {
        XCTAssertEqual(PortDetector.merge(logPort: 3080, lsofPorts: [], consecutiveEmptyLsof: 2), 3080)
        XCTAssertNil(PortDetector.merge(logPort: nil, lsofPorts: [], consecutiveEmptyLsof: 3))
    }

    func testLsofParser() {
        let sample = """
        COMMAND   PID USER   FD   TYPE     DEVICE SIZE/OFF NODE NAME
        node    12345 me   23u  IPv4 0x0      0t0  TCP 127.0.0.1:5173 (LISTEN)
        node    12345 me   24u  IPv4 0x0      0t0  TCP *:24678 (LISTEN)
        """
        XCTAssertEqual(Set(LsofParser.ports(fromStandardOutput: sample)), [5173, 24678])
    }
}
