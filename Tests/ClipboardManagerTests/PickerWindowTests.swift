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
        store.add(.text("entry to show"))

        PickerWindow.shared.show(history: store)

        XCTAssertTrue(PickerWindow.shared.isShowingPanel)
    }

    func testHideDismissesThePanel() {
        let store = ClipboardStore()
        store.add(.text("entry to show"))

        PickerWindow.shared.show(history: store)
        PickerWindow.shared.hide()

        XCTAssertFalse(PickerWindow.shared.isShowingPanel)
    }

    /// Regression test for the actual root cause of digit keys doing
    /// nothing: NSPanel's default canBecomeKey/canBecomeMain return false
    /// for a borderless + nonactivatingPanel window, so makeKeyAndOrderFront
    /// orders the panel to the front visually but it never actually
    /// receives keyboard events. Confirmed with a real synthetic keystroke
    /// via System Events during manual testing; this locks in the fix.
    func testPanelCanBecomeKeyAndMain() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    /// Regression test for Escape doing nothing: onExitCommand,
    /// onKeyPress(.escape), and overriding cancelOperation: on the panel
    /// were all tried and, with real keystrokes, verified not to reliably
    /// reach this borderless nonactivating panel - the row list's
    /// underlying NSTableView swallows cancelOperation: itself. A local
    /// keyDown event monitor is what actually works, so this drives it
    /// directly with a synthetic escape key event.
    func testEscapeClosesThePanel() {
        let store = ClipboardStore()
        store.add(.text("entry to show"))
        PickerWindow.shared.show(history: store)

        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 53
        )!
        _ = PickerWindow.shared.handleKeyDown(escapeEvent)

        XCTAssertFalse(PickerWindow.shared.isShowingPanel)
    }
}
