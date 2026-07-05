import XCTest
@testable import ClipboardManager

@MainActor
final class PickerNumberKeyTests: XCTestCase {
    /// Builds entries directly (newest-first, matching the order
    /// ClipboardStore.add would produce) rather than through a
    /// ClipboardStore, whose SwiftData-backed entries would become invalid
    /// once that transient store went out of scope.
    private func entries(_ texts: String...) -> [ClipboardEntry] {
        texts.reversed().map { ClipboardEntry(content: .text($0)) }
    }

    func testDigit1SelectsMostRecentEntry() {
        let entries = entries("first", "second", "third")

        let result = PickerNumberKey.entry(forDigit: "1", in: entries)

        XCTAssertEqual(result?.content, .text("third"))
    }

    func testDigit2SelectsThePreviousEntry() {
        let entries = entries("first", "second", "third")

        let result = PickerNumberKey.entry(forDigit: "2", in: entries)

        XCTAssertEqual(result?.content, .text("second"))
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

        XCTAssertEqual(result?.content, .text("1"))
    }
}
