import AppKit

/// Shared by `PickerWindow` and `HistoryWindow`: both need to remember
/// whichever app was frontmost before they activated themselves, then hand
/// focus back to it when they close - and, if the user picked an entry,
/// wait for that reactivation to actually complete (it's asynchronous)
/// before synthesizing the paste keystroke, or it can race ahead and land
/// in the wrong place.
@MainActor
struct PreviousAppRestorer {
    private(set) var previouslyActiveApp: NSRunningApplication?

    mutating func capture() {
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
    }

    /// Captures an already-known app instead of reading
    /// `NSWorkspace.shared.frontmostApplication` live - for handoffs
    /// between our own windows, where "currently frontmost" would just be
    /// ourselves rather than whichever external app was active before we
    /// ever took focus.
    mutating func capture(_ app: NSRunningApplication?) {
        previouslyActiveApp = app
    }

    mutating func restore(thenPaste entry: ClipboardEntry?, store: ClipboardStore? = nil) {
        let appToRestore = previouslyActiveApp
        previouslyActiveApp = nil
        appToRestore?.activate(options: [])

        guard let entry else { return }
        // ClipboardEntry is a SwiftData @Model class (a reference type
        // tied to its ModelContext's actor), so passing it into a plain
        // DispatchQueue closure - which the compiler can't prove runs on
        // the same actor - risks a data race under Swift 6 strict
        // concurrency. A MainActor-isolated Task keeps the same delay
        // while staying provably on the actor `entry` belongs to.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            PasteService.paste(entry, into: store)
        }
    }
}
