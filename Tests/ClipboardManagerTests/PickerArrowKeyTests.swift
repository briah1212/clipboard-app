import XCTest
@testable import ClipboardManager

final class PickerArrowKeyTests: XCTestCase {
    private func entries(_ texts: String...) -> [ClipboardEntry] {
        let store = ClipboardStore()
        for text in texts {
            store.add(.text(text))
        }
        return store.entries
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
