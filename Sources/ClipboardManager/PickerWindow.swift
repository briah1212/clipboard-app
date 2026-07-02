import SwiftUI
import AppKit

@MainActor
final class PickerWindow: NSObject {
    static let shared = PickerWindow()

    private var panel: NSPanel?

    /// Exposed for tests; production code should not need to inspect this.
    var isShowingPanel: Bool { panel?.isVisible ?? false }

    func show(history: ClipboardStore) {
        let view = PickerView(
            entries: history.entries,
            onSelect: { [weak self] entry in
                PasteService.paste(entry)
                self?.hide()
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 360)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.center()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        // Accessory apps never become the active app on their own; without
        // this, the panel can appear but never gets a real WindowServer
        // handoff, so it renders blank and swallows no input.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
    }

    func hide() {
        guard let panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        panel.close()
        self.panel = nil
    }

    @objc private func panelDidResignKey() {
        hide()
    }
}

private struct PickerView: View {
    let entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void
    let onClose: () -> Void

    @State private var selection: UUID?

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .onExitCommand(perform: onClose)
        .onAppear { selection = entries.first?.id }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 420, height: 360)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        List(entries, selection: $selection) { entry in
            Button {
                onSelect(entry)
            } label: {
                Text(entry.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) {
            guard let selection, let entry = entries.first(where: { $0.id == selection }) else {
                return .ignored
            }
            onSelect(entry)
            return .handled
        }
    }

    private var emptyState: some View {
        Text("No clipboard history yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
