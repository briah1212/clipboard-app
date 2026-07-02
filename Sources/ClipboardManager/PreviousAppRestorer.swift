import AppKit

/// Shared by `PickerWindow` and `HistoryWindow`: both need to remember
/// whichever app was frontmost before they activated themselves, then hand
/// focus back to it when they close - and, if the user picked an entry,
/// wait for that reactivation to actually complete (it's asynchronous)
/// before synthesizing the paste keystroke, or it can race ahead and land
/// in the wrong place.
struct PreviousAppRestorer {
    private var previouslyActiveApp: NSRunningApplication?

    mutating func capture() {
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
    }

    mutating func restore(thenPaste entry: ClipboardEntry?) {
        let appToRestore = previouslyActiveApp
        previouslyActiveApp = nil
        appToRestore?.activate(options: [])

        guard let entry else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteService.paste(entry)
        }
    }
}
