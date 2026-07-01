import SwiftUI
import AppKit

final class PickerWindow {
    static let shared = PickerWindow()

    private var panel: NSPanel?

    func show(history: ClipboardStore) {
        let view = PickerView(entries: history.entries) { [weak self] entry in
            PasteService.paste(entry)
            self?.hide()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

private struct PickerView: View {
    let entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void

    var body: some View {
        List(entries) { entry in
            Text(entry.text)
                .lineLimit(1)
                .onTapGesture { onSelect(entry) }
        }
        .frame(width: 420, height: 320)
    }
}
