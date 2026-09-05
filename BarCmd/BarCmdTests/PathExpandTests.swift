import XCTest
@testable import BarCmd

final class PathExpandTests: XCTestCase {
    let home = "/Users/tester"

    func testNilUsesHome() {
        XCTAssertEqual(PathExpand.expand(nil, home: home).path, home)
    }

    func testTilde() {
        XCTAssertEqual(PathExpand.expand("~", home: home).path, home)
    }

    func testTildeSlash() {
        XCTAssertEqual(PathExpand.expand("~/src", home: home).path, "/Users/tester/src")
    }

    func testAbsoluteUnchanged() {
        XCTAssertEqual(PathExpand.expand("/tmp/work", home: home).path, "/tmp/work")
    }
}
