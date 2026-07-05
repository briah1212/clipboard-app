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
        store.add(.text("entry to show"))

        HistoryWindow.shared.show(history: store)

        XCTAssertTrue(HistoryWindow.shared.isShowingWindow)
    }

    func testHideDismissesTheWindow() {
        let store = ClipboardStore()
        store.add(.text("entry to show"))

        HistoryWindow.shared.show(history: store)
        HistoryWindow.shared.hide()

        XCTAssertFalse(HistoryWindow.shared.isShowingWindow)
    }

    /// The native red traffic-light button (and Cmd+W) invoke
    /// `performClose`, which - unlike calling `close()` directly - consults
    /// `windowShouldClose(_:)` first. That's the path `HistoryWindow`
    /// intercepts to redirect into its own `hide()` instead of letting
    /// AppKit actually close (and eventually deallocate) the window, so
    /// this drives `performClose` the same way a real click would.
    func testClosingViaNativeCloseButtonDismissesTheWindow() {
        let store = ClipboardStore()
        store.add(.text("entry to show"))

        HistoryWindow.shared.show(history: store)
        HistoryWindow.shared.window?.performClose(nil)

        XCTAssertFalse(HistoryWindow.shared.isShowingWindow)
    }

    /// The window instance itself must survive being hidden - re-showing
    /// after a hide (or a redirected native close) should reuse the same
    /// window rather than needing a fresh one.
    func testWindowSurvivesHideAndCanBeShownAgain() {
        let store = ClipboardStore()
        store.add(.text("entry to show"))

        HistoryWindow.shared.show(history: store)
        HistoryWindow.shared.window?.performClose(nil)
        HistoryWindow.shared.show(history: store)

        XCTAssertTrue(HistoryWindow.shared.isShowingWindow)
    }
}
