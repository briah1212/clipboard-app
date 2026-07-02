import Foundation
import Observation

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let sourceAppName: String?
}

@MainActor
@Observable
final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 200

    func add(_ text: String, sourceAppName: String? = nil) {
        let entry = ClipboardEntry(id: UUID(), text: text, timestamp: Date(), sourceAppName: sourceAppName)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
