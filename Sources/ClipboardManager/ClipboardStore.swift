import Foundation

/// The raw representation of a single copy event. Stored as plain
/// value types (not NSImage/NSColor) so ClipboardStore/PasteboardWatcher can
/// stay off the main actor; NSImage/NSColor get reconstructed transiently
/// only where they're actually rendered or pasted back.
enum ClipboardContent: Equatable, Sendable {
    case text(String)
    case image(Data)
    case fileURLs([URL])
    case color(ColorComponents)
}

struct ColorComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date
}

final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 200

    func add(_ content: ClipboardContent) {
        let entry = ClipboardEntry(id: UUID(), content: content, timestamp: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}
