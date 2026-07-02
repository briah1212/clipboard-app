import XCTest
@testable import ClipboardManager

@MainActor
final class HistoryFilterTests: XCTestCase {
    private func entries(_ texts: String...) -> [ClipboardEntry] {
        let store = ClipboardStore()
        for text in texts {
            store.add(text)
        }
        return store.entries
    }

    func testAllKindReturnsEverything() {
        let all = entries("plain text", "https://example.com", "func f() {}")

        let result = HistoryFilter.apply(entries: all, query: "", kind: .all)

        XCTAssertEqual(result.count, 3)
    }

    func testLinksKindReturnsOnlyLinks() {
        let all = entries("plain text", "https://example.com", "func f() {}")

        let result = HistoryFilter.apply(entries: all, query: "", kind: .links)

        XCTAssertEqual(result.map(\.text), ["https://example.com"])
    }

    func testCodeKindReturnsOnlyCode() {
        let all = entries("plain text", "https://example.com", "func f() {}")

        let result = HistoryFilter.apply(entries: all, query: "", kind: .code)

        XCTAssertEqual(result.map(\.text), ["func f() {}"])
    }

    func testQueryFiltersCaseInsensitively() {
        let all = entries("git commit -m fix", "npm install framer-motion")

        let result = HistoryFilter.apply(entries: all, query: "GIT", kind: .all)

        XCTAssertEqual(result.map(\.text), ["git commit -m fix"])
    }

    func testEmptyQueryMatchesEverything() {
        let all = entries("first", "second")

        let result = HistoryFilter.apply(entries: all, query: "", kind: .all)

        XCTAssertEqual(result.count, 2)
    }

    /// Regression coverage for PickerArrowKey.move used against a filtered
    /// (not raw) entries array: when the current selection drops out of
    /// the visible set, arrow navigation should snap to the top of the new
    /// filtered list rather than staying stale or crashing.
    func testArrowMoveFallsBackToFirstFilteredEntryWhenSelectionDropsOut() {
        let all = entries("https://example.com", "plain text")
        let selectedID = all.first(where: { $0.text == "plain text" })!.id

        let filtered = HistoryFilter.apply(entries: all, query: "", kind: .links)
        let newSelection = PickerArrowKey.move(.down, selection: selectedID, in: filtered)

        XCTAssertEqual(newSelection, filtered.first?.id)
    }
}
