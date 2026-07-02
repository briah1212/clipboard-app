import XCTest
@testable import ClipboardManager

final class HotkeyManagerTests: XCTestCase {
    func testMatchingHotKeyIDFiresOnTrigger() {
        let manager = HotkeyManager()
        var triggered = false
        manager.onTrigger = { triggered = true }

        manager.hotKeyPressed(id: HotkeyManager.hotKeyID.id)

        XCTAssertTrue(triggered)
    }

    func testMismatchedHotKeyIDDoesNotFire() {
        let manager = HotkeyManager()
        var triggered = false
        manager.onTrigger = { triggered = true }

        manager.hotKeyPressed(id: HotkeyManager.hotKeyID.id + 1)

        XCTAssertFalse(triggered)
    }

    func testStartRegistersRealSystemHotKeyAndStopUnregisters() {
        let manager = HotkeyManager()

        XCTAssertTrue(manager.start(), "expected RegisterEventHotKey to succeed")
        manager.stop()
    }
}
