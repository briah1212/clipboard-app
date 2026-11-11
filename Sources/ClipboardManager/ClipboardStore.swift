import Foundation
import Observation
import SwiftData

/// The raw representation of a single copy event. Stored as plain value
/// types (not NSImage/NSColor) so ClipboardStore/PasteboardWatcher can stay
/// off the main actor; NSImage/NSColor get reconstructed transiently only
/// where they're actually rendered or pasted back.
enum ClipboardContent: Codable, Equatable, Sendable {
    case text(String)
    case image(Data)
    case fileURLs([URL])
    case color(ColorComponents)
}

struct ColorComponents: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

@Model
final class ClipboardEntry: Identifiable {
    var id: UUID
    var timestamp: Date
    var sourceAppName: String?

    // Non-image content is stored as JSON-encoded Data rather than
    // `ClipboardContent` directly - a plain Data column is unambiguously
    // well-supported by SwiftData regardless of how well an enum with
    // associated values is natively modeled. `nil` means an image entry.
    private var contentData: Data?

    // Image bytes live in their own column with external storage, so
    // SwiftData writes large images as separate files next to the store and
    // only reads them when `content` is actually asked for (a preview or a
    // paste) - not on launch, and not while searching or filtering, which
    // only need `isImage`/`displayText`. Inlining them base64-encoded in the
    // JSON blob made every search keystroke decode every screenshot.
    @Attribute(.externalStorage) private var imageData: Data?

    // Decoded non-image content, so search and filtering don't re-run
    // JSONDecoder on every access. Images are deliberately not cached, so
    // their bytes don't stay resident for the whole history.
    @Transient private var decodedContent: ClipboardContent? = nil

    var isImage: Bool { contentData == nil }

    var content: ClipboardContent {
        if isImage { return .image(imageData ?? Data()) }
        if let decodedContent { return decodedContent }
        let decoded = contentData.flatMap { try? JSONDecoder().decode(ClipboardContent.self, from: $0) } ?? .text("")
        // A store from before external storage can still hold an image
        // inline in the JSON; read it, but don't keep its bytes resident.
        if case .image = decoded { return decoded }
        decodedContent = decoded
        return decoded
    }

    init(id: UUID = UUID(), content: ClipboardContent, timestamp: Date = Date(), sourceAppName: String? = nil) {
        self.id = id
        if case .image(let data) = content {
            self.imageData = data
            self.contentData = nil
        } else {
            self.contentData = (try? JSONEncoder().encode(content)) ?? Data()
            self.imageData = nil
        }
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
    }

    /// A plain-text representation usable for search, previews, and AI
    /// context regardless of content kind - not necessarily what gets
    /// pasted back (see PasteService for the kind-specific pasteboard
    /// write).
    var displayText: String {
        if isImage { return "Image" }
        switch content {
        case .text(let text):
            return text
        case .fileURLs(let urls):
            return urls.map(\.lastPathComponent).joined(separator: ", ")
        case .image:
            return "Image"
        case .color(let components):
            return components.hexString
        }
    }
}

@MainActor
@Observable
final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 1000
    private var suppressedContent: ClipboardContent?

    private let modelContainer: ModelContainer
    private var modelContext: ModelContext { modelContainer.mainContext }

    init(modelContainer: ModelContainer = ClipboardStore.makeDefaultContainer()) {
        self.modelContainer = modelContainer
        entries = ClipboardStore.fetchAll(from: modelContainer.mainContext)
    }

    func add(_ content: ClipboardContent, sourceAppName: String? = nil) {
        if suppressedContent == content {
            suppressedContent = nil
            return
        }
        // Copying the same thing again right after itself (e.g. hitting
        // Cmd+C twice) shouldn't pile up a second identical entry at the
        // top of the history - only a genuinely different copy in between
        // should let the same content back in.
        let newIsImage: Bool
        if case .image = content { newIsImage = true } else { newIsImage = false }
        // The kind check first, so a text copy never reads the previous
        // entry's image bytes just to find out they differ.
        if let first = entries.first, first.isImage == newIsImage, first.content == content {
            return
        }
        let entry = ClipboardEntry(content: content, timestamp: Date(), sourceAppName: sourceAppName)
        modelContext.insert(entry)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            for stale in entries.suffix(from: maxEntries) {
                modelContext.delete(stale)
            }
            entries.removeLast(entries.count - maxEntries)
        }
        try? modelContext.save()
    }

    func remove(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        modelContext.delete(entry)
        entries.removeAll { $0.id == id }
        try? modelContext.save()
    }

    /// Call right before writing `content` back onto the system pasteboard
    /// to paste a history entry, so the watcher's next poll - which will
    /// see exactly that write as a pasteboard change - doesn't record it
    /// as a brand-new copy and duplicate it in the history.
    func suppressNextCapture(of content: ClipboardContent) {
        suppressedContent = content
    }

    private static func fetchAll(from context: ModelContext) -> [ClipboardEntry] {
        let descriptor = FetchDescriptor<ClipboardEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Real clipboard managers (e.g. Maccy) persist history with SwiftData
    /// rather than a hand-rolled file format, for the same reasons this
    /// does: first-party, minimal boilerplate, and built-in in-memory mode
    /// for tests. Detects the test environment automatically (rather than
    /// requiring every one of this store's many `ClipboardStore()` call
    /// sites across the test suite to opt in) so tests never touch the
    /// real persisted history file.
    static func makeDefaultContainer() -> ModelContainer {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let configuration: ModelConfiguration
        if isRunningTests {
            // A bare `isStoredInMemoryOnly: true` configuration pools its
            // backing store across every ModelContainer with an equivalent
            // configuration in the same process, even with a distinct name
            // - so every test's `ClipboardStore()` would silently share
            // (and pollute) the same in-memory history. A genuinely
            // separate file per container in the OS temp directory
            // sidesteps that pooling entirely and still never touches the
            // real persisted history.
            let url = FileManager.default.temporaryDirectory
                .appending(path: "ClipboardManagerTests-\(UUID().uuidString).sqlite")
            configuration = ModelConfiguration(url: url)
        } else {
            let directory = URL.applicationSupportDirectory.appending(path: "ClipboardManager", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appending(path: "History.sqlite")
            configuration = ModelConfiguration(url: storeURL)

            if let container = try? ModelContainer(for: ClipboardEntry.self, configurations: configuration) {
                return container
            }
            // A store left over from an earlier, incompatible ClipboardEntry
            // schema (e.g. the pre-multi-type-content shape) fails lightweight
            // migration rather than throwing something recoverable in place -
            // there's no meaningful mapping from a missing/renamed column to
            // a new mandatory one. This is a single-laptop history file with
            // no migration guarantees, so start fresh rather than falling
            // back to in-memory, which would silently disable persistence for
            // good on every future launch too. The old files (including the
            // `.History_SUPPORT` folder holding externally stored images) are
            // set aside under an `Incompatible-<timestamp>-` prefix rather
            // than deleted, so a bad schema change never silently destroys
            // history.
            let prefix = "Incompatible-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))-"
            for name in ["History.sqlite", "History.sqlite-wal", "History.sqlite-shm", ".History_SUPPORT"] {
                let source = directory.appending(path: name)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try? FileManager.default.moveItem(at: source, to: directory.appending(path: prefix + name))
            }
            if let container = try? ModelContainer(for: ClipboardEntry.self, configurations: configuration) {
                return container
            }
        }

        // Last resort if even a fresh on-disk store can't be created (e.g.
        // a permissions problem) - keeps the app usable instead of crashing
        // on every launch, at the cost of history not persisting.
        return try! ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
