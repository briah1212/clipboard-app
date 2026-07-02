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
    private var suppressedText: String?

    func add(_ text: String, sourceAppName: String? = nil) {
        if suppressedText == text {
            suppressedText = nil
            return
        }
        let entry = ClipboardEntry(id: UUID(), text: text, timestamp: Date(), sourceAppName: sourceAppName)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Call right before writing `text` back onto the system pasteboard to
    /// paste a history entry, so the watcher's next poll - which will see
    /// exactly that write as a pasteboard change - doesn't record it as a
    /// brand-new copy and duplicate it in the history.
    func suppressNextCapture(of text: String) {
        suppressedText = text
    }
}
