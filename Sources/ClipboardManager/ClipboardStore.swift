import Foundation
import Observation
import SwiftData

@Model
final class ClipboardEntry: Identifiable {
    var id: UUID
    var text: String
    var timestamp: Date
    var sourceAppName: String?

    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), sourceAppName: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
    }
}

@MainActor
@Observable
final class ClipboardStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 200
    private var suppressedText: String?

    private let modelContainer: ModelContainer
    private var modelContext: ModelContext { modelContainer.mainContext }

    init(modelContainer: ModelContainer = ClipboardStore.makeDefaultContainer()) {
        self.modelContainer = modelContainer
        entries = ClipboardStore.fetchAll(from: modelContainer.mainContext)
    }

    func add(_ text: String, sourceAppName: String? = nil) {
        if suppressedText == text {
            suppressedText = nil
            return
        }
        let entry = ClipboardEntry(text: text, timestamp: Date(), sourceAppName: sourceAppName)
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

    /// Call right before writing `text` back onto the system pasteboard to
    /// paste a history entry, so the watcher's next poll - which will see
    /// exactly that write as a pasteboard change - doesn't record it as a
    /// brand-new copy and duplicate it in the history.
    func suppressNextCapture(of text: String) {
        suppressedText = text
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
        // `XCTestConfigurationFilePath` is only set by Xcode's own test
        // runner, not `swift test` - checking whether XCTest.framework is
        // actually loaded in this process works for both.
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let configuration: ModelConfiguration
        if isRunningTests {
            // `isStoredInMemoryOnly: true` pools its backing store across
            // every ModelContainer with an equivalent configuration in the
            // same process, even with a distinct name - so every test's
            // `ClipboardStore()` ended up silently sharing (and polluting)
            // the same in-memory history. A genuinely separate file per
            // container in the OS temp directory sidesteps that pooling
            // entirely and still never touches the real persisted history.
            let url = FileManager.default.temporaryDirectory
                .appending(path: "ClipboardManagerTests-\(UUID().uuidString).sqlite")
            configuration = ModelConfiguration(url: url)
        } else {
            let directory = URL.applicationSupportDirectory.appending(path: "ClipboardManager", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(url: directory.appending(path: "History.sqlite"))
        }

        if let container = try? ModelContainer(for: ClipboardEntry.self, configurations: configuration) {
            return container
        }
        // A broken/incompatible persisted store (e.g. after a future
        // schema change with no migration) shouldn't prevent the app from
        // launching at all - falling back to in-memory loses history but
        // keeps the app usable, rather than crashing on every launch.
        return try! ModelContainer(for: ClipboardEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
