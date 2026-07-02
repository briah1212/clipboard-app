import XCTest
import AppKit
@testable import ClipboardManager

final class PasteboardWatcherTests: XCTestCase {
    func testPollCapturesNewPasteboardText() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.setString("captured via watcher", forType: .string)
        watcher.pollNow()

        XCTAssertEqual(watcher.store.entries.first?.content, .text("captured via watcher"))
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

    func testPollCapturesFileURLs() throws {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        let fileURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        watcher.pollNow()

        guard case .fileURLs(let urls) = watcher.store.entries.first?.content else {
            return XCTFail("expected a fileURLs entry")
        }
        XCTAssertEqual(urls.map(\.standardizedFileURL), [fileURL.standardizedFileURL])
    }

    func testPollCapturesColor() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        pasteboard.writeObjects([NSColor(red: 1, green: 0, blue: 0, alpha: 1)])
        watcher.pollNow()

        guard case .color(let components) = watcher.store.entries.first?.content else {
            return XCTFail("expected a color entry")
        }
        XCTAssertEqual(components.red, 1, accuracy: 0.01)
        XCTAssertEqual(components.green, 0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 0, accuracy: 0.01)
    }

    func testPollCapturesImage() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        let tiffData = makeSmallImageTIFFData()

        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        watcher.pollNow()

        guard case .image(let pngData) = watcher.store.entries.first?.content else {
            return XCTFail("expected an image entry")
        }
        XCTAssertNotNil(NSBitmapImageRep(data: pngData), "stored image data should decode as PNG")
    }

    func testPollIgnoresConcealedCopies() {
        let pasteboard = NSPasteboard.general
        let watcher = PasteboardWatcher()

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("super secret password", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])
        watcher.pollNow()

        XCTAssertTrue(watcher.store.entries.isEmpty)
    }

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeSmallImageTIFFData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }
}
