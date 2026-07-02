import XCTest
import AppKit
@testable import ClipboardManager

@MainActor
final class PasteboardWatcherTests: XCTestCase {
    func testPollCapturesNewPasteboardText() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.setString("captured via watcher", forType: .string)
        watcher.pollNow()

        XCTAssertEqual(watcher.store.entries.first?.text, "captured via watcher")
    }

    func testPollIgnoresUnchangedPasteboard() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.setString("only once", forType: .string)
        watcher.pollNow()
        watcher.pollNow()

        XCTAssertEqual(watcher.store.entries.count, 1)
    }

    func testPollCapturesSourceAppName() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.setString("captured via watcher", forType: .string)
        watcher.pollNow()

        let expectedAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        XCTAssertEqual(watcher.store.entries.first?.sourceAppName, expectedAppName)
    }
}
