import XCTest
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {
    func testNewestEntryIsFirst() {
        let store = ClipboardStore()
        store.add(.text("first"))
        store.add(.text("second"))

        XCTAssertEqual(store.entries.map(\.content), [.text("second"), .text("first")])
    }

    func testCapsHistoryAt200Entries() {
        let store = ClipboardStore()
        for i in 0..<205 {
            store.add(.text("item \(i)"))
        }

        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(store.entries.first?.content, .text("item 204"))
        XCTAssertEqual(store.entries.last?.content, .text("item 5"))
    }
}
