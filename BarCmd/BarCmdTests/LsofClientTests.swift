import Darwin
import XCTest
@testable import BarCmd

final class LsofClientTests: XCTestCase {
    func testArgumentsJoinsPidsForLsof() {
        XCTAssertEqual(
            LsofCommand.arguments(pids: [10, 20]),
            ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", "10,20"]
        )
    }

    func testEmptyPidsReturnsNilArgumentsAndEmptyPortsWithoutSpawning() throws {
        XCTAssertNil(LsofCommand.arguments(pids: []))
        let ports = try RealLsofClient().listeningPorts(pids: [])
        XCTAssertEqual(ports, [])
    }

    func testListeningPortsOnSelfDoesNotCrash() {
        XCTAssertNoThrow(try RealLsofClient().listeningPorts(pids: [getpid()]))
    }
}
