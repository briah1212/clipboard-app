import AppKit

@MainActor
final class PasteboardWatcher {
    let store = ClipboardStore()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks the pasteboard once and captures a new entry if it changed
    /// since the last check. Called on a timer in production; called
    /// directly in tests to avoid depending on timer/run-loop timing.
    func pollNow() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Frontmost app at the moment we notice the pasteboard changed,
            // not at the moment the user actually copied - polling only
            // catches up to 0.4s later, so a copy immediately followed by
            // Cmd+Shift+V can occasionally misattribute the source app.
            store.add(text, sourceAppName: currentSourceAppName())
        }
    }

    private func currentSourceAppName() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        // If our own app is frontmost (e.g. a copy from inside the history
        // window's preview pane), there's no useful source app to report.
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return frontmost.localizedName
    }
}
