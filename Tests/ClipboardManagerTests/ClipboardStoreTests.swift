import XCTest
import SwiftData
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

    func testImageAndTextEntriesSurviveReopeningThePersistedStore() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ClipboardStoreReopen-\(UUID().uuidString).sqlite")
        let supportDirectory = url.deletingLastPathComponent().appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT")
        defer {
            for path in [url.path, url.path + "-wal", url.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }
            try? FileManager.default.removeItem(at: supportDirectory)
        }
        // Large enough that SwiftData's external storage writes it to a
        // separate file instead of keeping it inline.
        var imageBytes = Data(count: 500_000)
        imageBytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
        do {
            let store = ClipboardStore(modelContainer: try ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(url: url)))
            store.add(.text("hello"))
            store.add(.image(imageBytes))
        }

        let externalFiles = FileManager.default.enumerator(at: supportDirectory, includingPropertiesForKeys: nil)?.allObjects ?? []
        XCTAssertFalse(externalFiles.isEmpty, "image bytes should be written to external storage, not inline")

        let reopened = ClipboardStore(modelContainer: try ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(url: url)))

        XCTAssertEqual(reopened.entries.map(\.isImage), [true, false])
        XCTAssertEqual(reopened.entries.map(\.displayText), ["Image", "hello"])
        XCTAssertEqual(reopened.entries.first?.content, .image(imageBytes))
        XCTAssertEqual(reopened.entries.last?.content, .text("hello"))
        XCTAssertEqual(ClipboardEntryKind.classify(reopened.entries[0]), .image)
    }
}
