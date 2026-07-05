import XCTest
@testable import ClipboardManager

final class SemanticSearchCandidatesTests: XCTestCase {
    func testKeywordsDropsStopwordsAndPunctuation() {
        let keywords = SemanticSearchCandidates.keywords(from: "snippets that have github links about AI model skills")

        XCTAssertEqual(keywords, ["snippets", "github", "links", "ai", "model", "skills"])
    }

    func testKeywordsFromEmptyQueryIsEmpty() {
        XCTAssertEqual(SemanticSearchCandidates.keywords(from: "   "), [])
    }

    func testSelectPrefersEntriesMatchingKeywords() {
        let entries = [
            ClipboardEntry(content: .text("https://github.com/anthropics/claude-skills")),
            ClipboardEntry(content: .text("grocery list: milk, eggs, bread")),
            ClipboardEntry(content: .text("func loadModelSkills() { /* github integration */ }"))
        ]

        let shortlist = SemanticSearchCandidates.select(from: entries, query: "snippets with github about model skills", limit: 2)

        XCTAssertEqual(shortlist.count, 2)
        XCTAssertTrue(shortlist.allSatisfy { $0.displayText.lowercased().contains("github") })
    }

    func testSelectFallsBackToMostRecentWhenNoKeywordsMatch() {
        let entries = [
            ClipboardEntry(content: .text("first")),
            ClipboardEntry(content: .text("second")),
            ClipboardEntry(content: .text("third"))
        ]

        let shortlist = SemanticSearchCandidates.select(from: entries, query: "zzz nonexistent term", limit: 2)

        XCTAssertEqual(shortlist.map(\.displayText), ["first", "second"])
    }

    func testSelectFallsBackToMostRecentWhenQueryHasOnlyStopwords() {
        let entries = [ClipboardEntry(content: .text("first")), ClipboardEntry(content: .text("second"))]

        let shortlist = SemanticSearchCandidates.select(from: entries, query: "the that about", limit: 5)

        XCTAssertEqual(shortlist.map(\.displayText), ["first", "second"])
    }

    func testSelectRespectsLimit() {
        let entries = (0..<50).map { ClipboardEntry(content: .text("github snippet \($0)")) }

        let shortlist = SemanticSearchCandidates.select(from: entries, query: "github snippet", limit: 10)

        XCTAssertEqual(shortlist.count, 10)
    }

    func testSelectBoostsCodeKindWhenQueryMentionsSnippets() {
        let entries = [
            ClipboardEntry(content: .text("the word snippet appears here as plain text")),
            ClipboardEntry(content: .text("func snippet() { return 1 }"))
        ]

        let shortlist = SemanticSearchCandidates.select(from: entries, query: "snippets", limit: 1)

        XCTAssertEqual(shortlist.first?.displayText, "func snippet() { return 1 }")
    }
}
