import XCTest
import AppKit
@testable import ClipboardManager

/// Exercises the full vertical slice the app exists for: copy several things,
/// summon the picker via the hotkey, pick an older entry, paste it back.
final class CopyPickPasteFlowTests: XCTestCase {
    func testCopyMultipleThenPasteAnOlderEntry() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.setString("first copy", forType: .string)
        watcher.pollNow()

        pasteboard.clearContents()
        pasteboard.setString("second copy", forType: .string)
        watcher.pollNow()

        pasteboard.clearContents()
        pasteboard.setString("third copy", forType: .string)
        watcher.pollNow()

        XCTAssertEqual(
            watcher.store.entries.map(\.content),
            [.text("third copy"), .text("second copy"), .text("first copy")]
        )

        var pickerOpened = false
        let hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { pickerOpened = true }
        hotkeyManager.hotKeyPressed(id: HotkeyManager.hotKeyID.id)
        XCTAssertTrue(pickerOpened, "hotkey should summon the picker")

        let olderEntry = watcher.store.entries[1]
        XCTAssertEqual(olderEntry.content, .text("second copy"))

        PasteService.paste(olderEntry, simulateKeystroke: false)

        XCTAssertEqual(pasteboard.string(forType: .string), "second copy")
    }

    func testCopyColorThenPasteItBack() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.writeObjects([NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)])
        watcher.pollNow()

        guard case .color = watcher.store.entries.first?.content else {
            return XCTFail("expected a color entry")
        }

        PasteService.paste(watcher.store.entries[0], simulateKeystroke: false)

        let pastedColor = NSColor(from: pasteboard)
        XCTAssertNotNil(pastedColor)
        let rgb = pastedColor?.usingColorSpace(.deviceRGB)
        XCTAssertEqual(rgb?.redComponent ?? -1, 0.2, accuracy: 0.01)
        XCTAssertEqual(rgb?.greenComponent ?? -1, 0.4, accuracy: 0.01)
        XCTAssertEqual(rgb?.blueComponent ?? -1, 0.6, accuracy: 0.01)
    }
}
