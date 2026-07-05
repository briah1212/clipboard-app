import Foundation

/// Selects a small local shortlist of candidate entries before any network
/// call happens, so semantic search never ships the full clipboard history
/// to the API regardless of how large it grows - this is the mechanism
/// that keeps the feature both cheap and scalable. Kept as a pure function,
/// separate from the view and the network layer, so it's unit-testable
/// without touching either.
enum SemanticSearchCandidates {
    static let defaultLimit = 30

    private static let stopwords: Set<String> = [
        "a", "an", "the", "that", "this", "these", "those", "have", "has", "had",
        "about", "with", "for", "and", "or", "of", "to", "in", "on", "is", "are",
        "i", "me", "my", "want", "find", "show", "search", "get", "look", "looking"
    ]

    /// Lowercased, stopword-filtered terms extracted from a natural
    /// language query, used both for scoring and for the plain-substring
    /// fallback when the AI call fails.
    static func keywords(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
    }

    static func select(from entries: [ClipboardEntry], query: String, limit: Int = defaultLimit) -> [ClipboardEntry] {
        let terms = keywords(from: query)
        guard !terms.isEmpty else {
            return Array(entries.prefix(limit))
        }

        let scored = entries.map { entry -> (entry: ClipboardEntry, score: Int) in
            let haystack = entry.text.lowercased()
            var score = terms.reduce(0) { $1.isEmpty ? $0 : (haystack.contains($1) ? $0 + 1 : $0) }

            let kind = ClipboardEntryKind.classify(entry.text)
            if kind == .code, terms.contains(where: { $0 == "snippet" || $0 == "snippets" || $0 == "code" }) {
                score += 1
            }
            if kind == .link, terms.contains(where: { $0 == "link" || $0 == "links" || $0 == "url" || $0 == "github" }) {
                score += 1
            }
            return (entry, score)
        }

        let matched = scored.filter { $0.score > 0 }
        guard !matched.isEmpty else {
            return Array(entries.prefix(limit))
        }
        return matched
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.entry)
    }
}

enum SemanticSearchError: Error {
    case missingAPIKey
    case requestFailed
    case invalidResponse
}

/// The network seam - a protocol so tests can substitute a fake client
/// instead of hitting the real API, matching how PasteService's keystroke
/// synthesis is the only mocked seam elsewhere in this codebase. MainActor
/// because ClipboardEntry is a SwiftData @Model class (not Sendable), so
/// it can only safely cross this async boundary while pinned to the same
/// actor it - and the rest of this app's UI - already lives on.
@MainActor
protocol SemanticSearchClient {
    func rank(query: String, candidates: [ClipboardEntry]) async throws -> [UUID]
}

/// Calls the Anthropic Messages API with just the local candidate
/// shortlist (never the full history), a short truncated preview per
/// candidate (never the full pasted text), and a fast/cheap model tier -
/// this is what keeps the feature "minimal tokens" rather than shipping
/// everything to a large reasoning model. Forces the response through a
/// single tool call returning just matching ids, so the reply itself is
/// tiny and reliably parseable instead of free-form prose.
struct AnthropicSemanticSearchClient: SemanticSearchClient {
    private let apiKey: String
    private let model = "claude-haiku-4-5-20251001"
    private let previewLength = 150

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func rank(query: String, candidates: [ClipboardEntry]) async throws -> [UUID] {
        guard !candidates.isEmpty else { return [] }

        let items: [[String: Any]] = candidates.map { entry in
            [
                "id": entry.id.uuidString,
                "kind": ClipboardEntryKind.classify(entry.text).label,
                "app": entry.sourceAppName ?? "Unknown",
                "preview": String(entry.text.prefix(previewLength))
            ]
        }
        let itemsJSON = try JSONSerialization.data(withJSONObject: items)
        let itemsString = String(data: itemsJSON, encoding: .utf8) ?? "[]"

        let userContent = """
        Search request: \(query)

        Candidate clipboard entries (JSON array):
        \(itemsString)

        Call return_matches with the ids of candidates that satisfy the search request, ordered most relevant first. Omit ids that don't match.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "tools": [
                [
                    "name": "return_matches",
                    "description": "Return the ids of candidate clipboard entries matching the search request.",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "matching_ids": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["matching_ids"]
                    ]
                ]
            ],
            "tool_choice": ["type": "tool", "name": "return_matches"],
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SemanticSearchError.requestFailed
        }

        return try Self.parseMatchingIDs(from: data, validIDs: Set(candidates.map(\.id)))
    }

    private static func parseMatchingIDs(from data: Data, validIDs: Set<UUID>) throws -> [UUID] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]],
            let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolUse["input"] as? [String: Any],
            let rawIDs = input["matching_ids"] as? [String]
        else {
            throw SemanticSearchError.invalidResponse
        }
        // Only ever trust ids that were actually in the candidate set we
        // sent - guards against a malformed or hallucinated id reaching
        // the UI as a lookup that silently does nothing.
        return rawIDs.compactMap(UUID.init).filter { validIDs.contains($0) }
    }
}

/// Ties the local pre-filter and the network client together, with a
/// small in-session cache so retyping/resubmitting an identical query
/// against an unchanged history doesn't re-spend tokens on a repeat call.
@MainActor
final class SemanticSearchService {
    // Throwing rather than a plain `() -> SemanticSearchClient` so the
    // "no API key configured" case is only ever a concern for the real
    // production client - tests inject a fake client directly and never
    // need a Keychain entry to exist at all.
    private let makeClient: @MainActor () async throws -> SemanticSearchClient
    private var cache: [CacheKey: [UUID]] = [:]

    private struct CacheKey: Hashable {
        let query: String
        let candidateIDs: [UUID]
    }

    init(makeClient: @escaping @MainActor () async throws -> SemanticSearchClient = SemanticSearchService.defaultClient) {
        self.makeClient = makeClient
    }

    private static func defaultClient() async throws -> SemanticSearchClient {
        guard let apiKey = await KeychainStore.anthropicAPIKey(), !apiKey.isEmpty else {
            throw SemanticSearchError.missingAPIKey
        }
        return AnthropicSemanticSearchClient(apiKey: apiKey)
    }

    func search(query: String, in entries: [ClipboardEntry]) async throws -> [UUID] {
        let candidates = SemanticSearchCandidates.select(from: entries, query: query)
        let key = CacheKey(query: query, candidateIDs: candidates.map(\.id))
        if let cached = cache[key] {
            return cached
        }

        let client = try await makeClient()
        let ids = try await client.rank(query: query, candidates: candidates)
        cache[key] = ids
        return ids
    }
}
