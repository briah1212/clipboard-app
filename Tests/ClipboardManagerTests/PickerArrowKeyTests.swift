import XCTest
@testable import ClipboardManager

@MainActor
final class PickerArrowKeyTests: XCTestCase {
    /// Builds entries directly (newest-first, matching the order
    /// ClipboardStore.add would produce) rather than through a
    /// ClipboardStore, whose SwiftData-backed entries would become invalid
    /// once that transient store went out of scope.
    private func entries(_ texts: String...) -> [ClipboardEntry] {
        texts.reversed().map { ClipboardEntry(text: $0) }
    }

    func testDownMovesToTheNextEntry() {
        let entries = entries("first", "second", "third")

        let newSelection = PickerArrowKey.move(.down, selection: entries[0].id, in: entries)

        XCTAssertEqual(newSelection, entries[1].id)
    }

    func testUpMovesToThePreviousEntry() {
        let entries = entries("first", "second", "third")

        let newSelection = PickerArrowKey.move(.up, selection: entries[1].id, in: entries)

        XCTAssertEqual(newSelection, entries[0].id)
    }

    func testDownClampsAtTheLastEntry() {
        let entries = entries("first", "second")

        let newSelection = PickerArrowKey.move(.down, selection: entries[1].id, in: entries)

        XCTAssertEqual(newSelection, entries[1].id)
    }

    func testUpClampsAtTheFirstEntry() {
        let entries = entries("first", "second")

        let newSelection = PickerArrowKey.move(.up, selection: entries[0].id, in: entries)

        XCTAssertEqual(newSelection, entries[0].id)
    }

    func testNoCurrentSelectionMovesToTheFirstEntry() {
        let entries = entries("first", "second")

        XCTAssertEqual(PickerArrowKey.move(.down, selection: nil, in: entries), entries[0].id)
        XCTAssertEqual(PickerArrowKey.move(.up, selection: nil, in: entries), entries[0].id)
    }

    func testEmptyHistoryReturnsNil() {
        XCTAssertNil(PickerArrowKey.move(.down, selection: nil, in: []))
    }
}
