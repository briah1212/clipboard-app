import XCTest
@testable import ClipboardManager

final class PickerNumberKeyTests: XCTestCase {
    private func entries(_ texts: String...) -> [ClipboardEntry] {
        let store = ClipboardStore()
        for text in texts {
            store.add(text)
        }
        return store.entries
    }

    func testDigit1SelectsMostRecentEntry() {
        let entries = entries("first", "second", "third")

        let result = PickerNumberKey.entry(forDigit: "1", in: entries)

        XCTAssertEqual(result?.text, "third")
    }

    func testDigit2SelectsThePreviousEntry() {
        let entries = entries("first", "second", "third")

        let result = PickerNumberKey.entry(forDigit: "2", in: entries)

        XCTAssertEqual(result?.text, "second")
    }

    func testDigitBeyondHistoryCountReturnsNil() {
        let entries = entries("only one")

        XCTAssertNil(PickerNumberKey.entry(forDigit: "2", in: entries))
    }

    func testDigitZeroReturnsNil() {
        let entries = entries("first")

        XCTAssertNil(PickerNumberKey.entry(forDigit: "0", in: entries))
    }

    func testNonDigitCharacterReturnsNil() {
        let entries = entries("first")

        XCTAssertNil(PickerNumberKey.entry(forDigit: "a", in: entries))
    }

    func testDigit9SelectsTheNinthEntry() {
        let entries = entries("1", "2", "3", "4", "5", "6", "7", "8", "9")

        let result = PickerNumberKey.entry(forDigit: "9", in: entries)

        XCTAssertEqual(result?.text, "1")
    }
}
