import XCTest
import AppKit
@testable import ClipboardManager

/// Exercises the full vertical slice the app exists for: copy several things,
/// summon the picker via the hotkey, pick an older entry, paste it back.
@MainActor
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

        XCTAssertEqual(watcher.store.entries.map(\.text), ["third copy", "second copy", "first copy"])

        var pickerOpened = false
        let hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { pickerOpened = true }
        hotkeyManager.hotKeyPressed(id: HotkeyManager.hotKeyID.id)
        XCTAssertTrue(pickerOpened, "hotkey should summon the picker")

        let olderEntry = watcher.store.entries[1]
        XCTAssertEqual(olderEntry.text, "second copy")

        PasteService.paste(olderEntry, into: watcher.store, simulateKeystroke: false)

        XCTAssertEqual(pasteboard.string(forType: .string), "second copy")

        // Pasting writes the entry's text back onto the pasteboard to prep
        // the Cmd+V, which the watcher's next poll would otherwise see as
        // a brand-new external copy and re-add as a duplicate.
        let countBeforePoll = watcher.store.entries.count
        watcher.pollNow()

        XCTAssertEqual(watcher.store.entries.count, countBeforePoll, "pasting should not be recaptured as a new copy")
        XCTAssertEqual(watcher.store.entries.map(\.text), ["third copy", "second copy", "first copy"])
    }
}
