import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PickerWindowTests: XCTestCase {
    override func tearDown() {
        PickerWindow.shared.hide()
        super.tearDown()
    }

    func testShowPresentsAVisiblePanel() {
        let store = ClipboardStore()
        store.add("entry to show")

        PickerWindow.shared.show(history: store)

        XCTAssertTrue(PickerWindow.shared.isShowingPanel)
    }

    func testHideDismissesThePanel() {
        let store = ClipboardStore()
        store.add("entry to show")

        PickerWindow.shared.show(history: store)
        PickerWindow.shared.hide()

        XCTAssertFalse(PickerWindow.shared.isShowingPanel)
    }
}
