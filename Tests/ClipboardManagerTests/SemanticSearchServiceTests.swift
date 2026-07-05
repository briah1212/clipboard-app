import XCTest
@testable import ClipboardManager

@MainActor
private final class FakeSemanticSearchClient: SemanticSearchClient {
    var callCount = 0
    var lastQuery: String?
    var lastCandidateCount: Int?
    var resultToReturn: [UUID] = []

    func rank(query: String, candidates: [ClipboardEntry]) async throws -> [UUID] {
        callCount += 1
        lastQuery = query
        lastCandidateCount = candidates.count
        return resultToReturn
    }
}

@MainActor
final class SemanticSearchServiceTests: XCTestCase {
    func testSearchReturnsClientRankedIDs() async throws {
        let entries = [ClipboardEntry(text: "github snippet"), ClipboardEntry(text: "grocery list")]
        let fake = FakeSemanticSearchClient()
        fake.resultToReturn = [entries[0].id]
        let service = SemanticSearchService { fake }

        let ids = try await service.search(query: "github", in: entries)

        XCTAssertEqual(ids, [entries[0].id])
        XCTAssertEqual(fake.callCount, 1)
    }

    func testSearchOnlyPassesTheLocalShortlistNotTheFullHistory() async throws {
        // Only entries mentioning "github" should survive the local
        // pre-filter and reach the client - this is what guarantees the
        // full history is never shipped to the network.
        let entries = (0..<40).map { ClipboardEntry(text: $0 == 0 ? "github snippet" : "unrelated item \($0)") }
        let fake = FakeSemanticSearchClient()
        let service = SemanticSearchService { fake }

        _ = try await service.search(query: "github", in: entries)

        XCTAssertEqual(fake.lastCandidateCount, 1)
    }

    func testRepeatedIdenticalSearchIsServedFromCacheNotTheNetwork() async throws {
        let entries = [ClipboardEntry(text: "github snippet")]
        let fake = FakeSemanticSearchClient()
        fake.resultToReturn = [entries[0].id]
        let service = SemanticSearchService { fake }

        _ = try await service.search(query: "github", in: entries)
        _ = try await service.search(query: "github", in: entries)

        XCTAssertEqual(fake.callCount, 1, "second identical search should be served from cache")
    }

    func testDifferentQueryIsNotServedFromAnotherQuerysCache() async throws {
        let entries = [ClipboardEntry(text: "github snippet")]
        let fake = FakeSemanticSearchClient()
        let service = SemanticSearchService { fake }

        _ = try await service.search(query: "github", in: entries)
        _ = try await service.search(query: "something else entirely", in: entries)

        XCTAssertEqual(fake.callCount, 2)
    }
}
