import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class HistoryWindowTests: XCTestCase {
    override func tearDown() {
        HistoryWindow.shared.hide()
        super.tearDown()
    }

    func testShowPresentsAVisibleWindow() {
        let store = ClipboardStore()
        store.add("entry to show")

        HistoryWindow.shared.show(history: store)

        XCTAssertTrue(HistoryWindow.shared.isShowingWindow)
    }

    func testHideDismissesTheWindow() {
        let store = ClipboardStore()
        store.add("entry to show")

        HistoryWindow.shared.show(history: store)
        HistoryWindow.shared.hide()

        XCTAssertFalse(HistoryWindow.shared.isShowingWindow)
    }
}
