import XCTest
@testable import ClipboardManager

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testNewestEntryIsFirst() {
        let store = ClipboardStore()
        store.add(.text("first"))
        store.add(.text("second"))

        XCTAssertEqual(store.entries.map(\.content), [.text("second"), .text("first")])
    }

    func testCapsHistoryAt1000Entries() {
        let store = ClipboardStore()
        for i in 0..<1005 {
            store.add(.text("item \(i)"))
        }

        XCTAssertEqual(store.entries.count, 1000)
        XCTAssertEqual(store.entries.first?.content, .text("item 1004"))
        XCTAssertEqual(store.entries.last?.content, .text("item 5"))
    }

    func testStoresSourceAppName() {
        let store = ClipboardStore()
        store.add(.text("copied text"), sourceAppName: "Terminal")

        XCTAssertEqual(store.entries.first?.sourceAppName, "Terminal")
    }

    func testSourceAppNameDefaultsToNil() {
        let store = ClipboardStore()
        store.add(.text("copied text"))

        XCTAssertNil(store.entries.first?.sourceAppName)
    }

    func testRemoveDeletesMatchingEntry() {
        let store = ClipboardStore()
        store.add(.text("first"))
        store.add(.text("second"))
        let idToRemove = store.entries.first(where: { $0.content == .text("first") })!.id

        store.remove(id: idToRemove)

        XCTAssertEqual(store.entries.map(\.content), [.text("second")])
    }

    func testSuppressedTextIsNotRecapturedOnNextAdd() {
        let store = ClipboardStore()
        store.add(.text("first"))
        store.suppressNextCapture(of: .text("first"))

        store.add(.text("first"))

        XCTAssertEqual(store.entries.map(\.content), [.text("first")], "the suppressed re-capture should not duplicate the entry")
    }

    func testSuppressionOnlyAppliesOnce() {
        let store = ClipboardStore()
        store.suppressNextCapture(of: .text("first"))

        store.add(.text("first"))
        store.add(.text("first"))

        XCTAssertEqual(store.entries.map(\.content), [.text("first")], "only the first matching add should be suppressed - the second is a real new copy")
    }

    func testSuppressionDoesNotAffectDifferentText() {
        let store = ClipboardStore()
        store.suppressNextCapture(of: .text("first"))

        store.add(.text("second"))

        XCTAssertEqual(store.entries.map(\.content), [.text("second")])
    }

    func testConsecutiveDuplicateCopyIsNotAddedAgain() {
        let store = ClipboardStore()
        store.add(.text("repeated"))

        store.add(.text("repeated"))
        store.add(.text("repeated"))

        XCTAssertEqual(store.entries.map(\.content), [.text("repeated")])
    }

    func testDuplicateCopyIsReAddedIfSomethingElseCameInBetween() {
        let store = ClipboardStore()
        store.add(.text("first"))
        store.add(.text("second"))

        store.add(.text("first"))

        XCTAssertEqual(store.entries.map(\.content), [.text("first"), .text("second"), .text("first")])
    }

    func testConsecutiveDuplicateNonTextContentIsNotAddedAgain() {
        let store = ClipboardStore()
        let color = ColorComponents(red: 1, green: 0, blue: 0, alpha: 1)
        store.add(.color(color))

        store.add(.color(color))

        XCTAssertEqual(store.entries.map(\.content), [.color(color)])
    }
}
