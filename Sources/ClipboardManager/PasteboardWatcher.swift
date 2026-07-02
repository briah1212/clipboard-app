import AppKit

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
            self?.pollNow()
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
            store.add(text)
        }
    }
}
