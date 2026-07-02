import XCTest
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {
    func testNewestEntryIsFirst() {
        let store = ClipboardStore()
        store.add("first")
        store.add("second")

        XCTAssertEqual(store.entries.map(\.text), ["second", "first"])
    }

    func testCapsHistoryAt200Entries() {
        let store = ClipboardStore()
        for i in 0..<205 {
            store.add("item \(i)")
        }

        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(store.entries.first?.text, "item 204")
        XCTAssertEqual(store.entries.last?.text, "item 5")
    }
}
