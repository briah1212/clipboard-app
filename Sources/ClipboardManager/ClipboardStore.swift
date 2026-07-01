import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
}

final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 200

    func add(_ text: String) {
        let entry = ClipboardEntry(id: UUID(), text: text, timestamp: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}
