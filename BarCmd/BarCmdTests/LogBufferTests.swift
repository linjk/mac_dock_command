import XCTest
@testable import BarCmd

final class LogBufferTests: XCTestCase {
    func testAppendAndRead() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "\u{001B}[31ma\u{001B}[0m")
        XCTAssertEqual(store.lines(id: id), ["a"])
    }

    func testRingDropsOldest() {
        let store = LogBufferStore()
        let id = UUID()
        for i in 0..<(LogBufferStore.capacity + 3) {
            store.append(id: id, line: "\(i)")
        }
        let lines = store.lines(id: id)
        XCTAssertEqual(lines.count, LogBufferStore.capacity)
        XCTAssertEqual(lines.first, "3")
        XCTAssertEqual(lines.last, "\(LogBufferStore.capacity + 2)")
    }

    func testClearKeepsSlot() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "x")
        store.clear(id: id)
        XCTAssertEqual(store.lines(id: id), [])
    }

    func testRemoveDrops() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "x")
        store.remove(id: id)
        XCTAssertEqual(store.lines(id: id), [])
    }
}
