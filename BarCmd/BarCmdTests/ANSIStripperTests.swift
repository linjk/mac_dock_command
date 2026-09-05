import XCTest
@testable import BarCmd

final class ANSIStripperTests: XCTestCase {
    func testStripsCSI() {
        let raw = "\u{001B}[32mhello\u{001B}[0m world"
        XCTAssertEqual(ANSIStripper.strip(raw), "hello world")
    }

    func testStripsViteLike() {
        let raw = "\u{001B}[1m\u{001B}[32m  ➜  Local: \u{001B}[0m http://localhost:5173/"
        XCTAssertEqual(ANSIStripper.strip(raw), "  ➜  Local:  http://localhost:5173/")
    }

    func testStripsOSC() {
        let raw = "\u{001B}]8;;http://x\u{0007}link\u{001B}]8;;\u{0007}"
        XCTAssertEqual(ANSIStripper.strip(raw), "link")
    }

    func testPlainUnchanged() {
        XCTAssertEqual(ANSIStripper.strip("ok"), "ok")
    }
}
