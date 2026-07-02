import XCTest
@testable import ClipboardManager

@MainActor
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

    func testStoresSourceAppName() {
        let store = ClipboardStore()
        store.add("copied text", sourceAppName: "Terminal")

        XCTAssertEqual(store.entries.first?.sourceAppName, "Terminal")
    }

    func testSourceAppNameDefaultsToNil() {
        let store = ClipboardStore()
        store.add("copied text")

        XCTAssertNil(store.entries.first?.sourceAppName)
    }

    func testRemoveDeletesMatchingEntry() {
        let store = ClipboardStore()
        store.add("first")
        store.add("second")
        let idToRemove = store.entries.first(where: { $0.text == "first" })!.id

        store.remove(id: idToRemove)

        XCTAssertEqual(store.entries.map(\.text), ["second"])
    }

    func testSuppressedTextIsNotRecapturedOnNextAdd() {
        let store = ClipboardStore()
        store.add("first")
        store.suppressNextCapture(of: "first")

        store.add("first")

        XCTAssertEqual(store.entries.map(\.text), ["first"], "the suppressed re-capture should not duplicate the entry")
    }

    func testSuppressionOnlyAppliesOnce() {
        let store = ClipboardStore()
        store.suppressNextCapture(of: "first")

        store.add("first")
        store.add("first")

        XCTAssertEqual(store.entries.map(\.text), ["first"], "only the first matching add should be suppressed - the second is a real new copy")
    }

    func testSuppressionDoesNotAffectDifferentText() {
        let store = ClipboardStore()
        store.suppressNextCapture(of: "first")

        store.add("second")

        XCTAssertEqual(store.entries.map(\.text), ["second"])
    }
}
