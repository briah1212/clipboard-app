import XCTest
@testable import ClipboardManager

final class ClipboardEntryKindTests: XCTestCase {
    func testClassifiesAURLAsLink() {
        XCTAssertEqual(ClipboardEntryKind.classify("https://developer.apple.com/documentation/appkit/nspanel"), .link)
    }

    func testClassifiesAWWWPrefixedURLAsLink() {
        XCTAssertEqual(ClipboardEntryKind.classify("www.example.com"), .link)
    }

    func testClassifiesACodeSnippetAsCode() {
        XCTAssertEqual(ClipboardEntryKind.classify("func applicationDidFinishLaunching(_ notification: Notification) {}"), .code)
    }

    func testClassifiesPlainSentenceAsText() {
        XCTAssertEqual(ClipboardEntryKind.classify("Let's sync tomorrow at 10:30 - does that work for you?"), .text)
    }

    func testDoesNotClassifySentenceMentioningAURLAsLink() {
        XCTAssertEqual(ClipboardEntryKind.classify("check out https://example.com when you get a chance"), .text)
    }
}
