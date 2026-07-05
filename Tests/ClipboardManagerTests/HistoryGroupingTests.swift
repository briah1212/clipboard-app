import XCTest
@testable import ClipboardManager

final class HistoryGroupingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!

    private func entry(_ text: String, daysAgo: Int, hoursAgo: Int = 0) -> ClipboardEntry {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let timestamp = calendar.date(byAdding: .hour, value: -hoursAgo, to: date)!
        return ClipboardEntry(id: UUID(), content: .text(text), timestamp: timestamp, sourceAppName: nil)
    }

    func testGroupsIntoTodayYesterdayAndOlder() {
        let entries = [
            entry("today item", daysAgo: 0),
            entry("yesterday item", daysAgo: 1),
            entry("older item", daysAgo: 5)
        ]

        let groups = HistoryGrouping.grouped(entries: entries, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.sectionTitle), ["Today", "Yesterday", "Jun 27"])
        XCTAssertEqual(groups[0].entries.map(\.displayText), ["today item"])
        XCTAssertEqual(groups[1].entries.map(\.displayText), ["yesterday item"])
        XCTAssertEqual(groups[2].entries.map(\.displayText), ["older item"])
    }

    func testMultipleEntriesOnSameDayShareASection() {
        let entries = [
            entry("first today", daysAgo: 0, hoursAgo: 1),
            entry("second today", daysAgo: 0, hoursAgo: 3)
        ]

        let groups = HistoryGrouping.grouped(entries: entries, now: now, calendar: calendar)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sectionTitle, "Today")
        XCTAssertEqual(groups[0].entries.count, 2)
    }

    func testEmptyEntriesProducesNoGroups() {
        let groups = HistoryGrouping.grouped(entries: [], now: now, calendar: calendar)

        XCTAssertTrue(groups.isEmpty)
    }
}
