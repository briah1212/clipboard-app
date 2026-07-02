import SwiftUI
import AppKit

/// NSPanel's default canBecomeKey/canBecomeMain return false for a
/// borderless + nonactivatingPanel window unless overridden, so without
/// this subclass makeKeyAndOrderFront() orders the panel to the front
/// visually but it never actually becomes key - meaning it never receives
/// real keyboard events at all, even while its owning app is active.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PickerWindow: NSObject {
    static let shared = PickerWindow()

    private var panel: NSPanel?
    private var previouslyActiveApp: NSRunningApplication?

    /// Exposed for tests; production code should not need to inspect this.
    var isShowingPanel: Bool { panel?.isVisible ?? false }

    func show(history: ClipboardStore) {
        // .nonactivatingPanel alone was not enough to actually receive
        // digit keystrokes: on macOS only the active application's key
        // window gets real hardware key events, so without activating
        // ourselves the panel appeared but number keys leaked straight
        // through to whatever field was focused underneath it. So we do
        // activate - but we remember who was frontmost first and hand
        // focus straight back to them in hide(), so the picker never
        // outlives the moment the user is actually choosing an entry.
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication

        let view = PickerView(
            entries: history.entries,
            onSelect: { [weak self] entry in
                self?.hide(thenPaste: entry)
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 360)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]

        let panel = KeyablePanel(
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

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
    }

    func hide() {
        hide(thenPaste: nil)
    }

    private func hide(thenPaste entry: ClipboardEntry?) {
        guard let panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        panel.close()
        self.panel = nil

        let appToRestore = previouslyActiveApp
        previouslyActiveApp = nil
        appToRestore?.activate(options: [])

        guard let entry else { return }
        // Reactivating another app is asynchronous; posting the paste
        // keystroke immediately can race ahead of it and land in the
        // wrong place (or nowhere). A short delay lets the reactivation
        // actually complete first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteService.paste(entry)
        }
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
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .focusable()
        .focused($isFocused)
        .onExitCommand(perform: onClose)
        .onAppear {
            selection = entries.first?.id
            // SwiftUI's onKeyPress only fires for a view that holds SwiftUI
            // focus, which is separate from AppKit's key-window status.
            // makeKeyAndOrderFront() alone doesn't give any view focus, so
            // without this, digit keys were silently swallowed - the panel
            // was key at the AppKit level but nothing owned SwiftUI focus.
            isFocused = true
        }
        .onKeyPress(characters: .decimalDigits) { keyPress in
            guard let character = keyPress.characters.first,
                  let entry = PickerNumberKey.entry(forDigit: character, in: entries) else {
                return .ignored
            }
            onSelect(entry)
            return .handled
        }
        .onKeyPress(.return) {
            guard let selection, let entry = entries.first(where: { $0.id == selection }) else {
                return .ignored
            }
            onSelect(entry)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = PickerArrowKey.move(.up, selection: selection, in: entries)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selection = PickerArrowKey.move(.down, selection: selection, in: entries)
            return .handled
        }
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
        VStack(alignment: .leading, spacing: 2) {
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
            if !entries.isEmpty {
                Text("Press 1-9 to paste, Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(index: index, entry: entry)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(index: Int, entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
            rowContent(for: entry.content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(entry) }
    }

    @ViewBuilder
    private func rowContent(for content: ClipboardContent) -> some View {
        switch content {
        case .text(let text):
            Text(text)
                .lineLimit(1)
        case .fileURLs(let urls):
            HStack(spacing: 6) {
                if let first = urls.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(fileLabel(for: urls))
                    .lineLimit(1)
            }
        case .image(let pngData):
            HStack(spacing: 8) {
                if let nsImage = NSImage(data: pngData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text("Image")
                    .lineLimit(1)
            }
        case .color(let components):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: components.red, green: components.green, blue: components.blue, opacity: components.alpha))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                Text(hexString(for: components))
                    .lineLimit(1)
            }
        }
    }

    private func fileLabel(for urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        guard urls.count > 1 else { return first.lastPathComponent }
        return "\(urls.count) files: \(first.lastPathComponent)"
    }

    private func hexString(for components: ColorComponents) -> String {
        let red = Int((components.red * 255).rounded())
        let green = Int((components.green * 255).rounded())
        let blue = Int((components.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private var emptyState: some View {
        Text("No clipboard history yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Maps a pressed digit key (1-9) to the corresponding history entry: 1 is
/// the most recent copy, 2 the one before that, and so on. Kept separate
/// from the view so the mapping is testable without driving real key events
/// through SwiftUI.
enum PickerNumberKey {
    static func entry(forDigit character: Character, in entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard let digit = character.wholeNumberValue, (1...9).contains(digit) else {
            return nil
        }
        let index = digit - 1
        guard entries.indices.contains(index) else {
            return nil
        }
        return entries[index]
    }
}

/// Computes the next selected entry id for up/down arrow navigation,
/// clamped at either end of the history. Kept separate from the view so
/// it's unit-testable without driving real SwiftUI key events.
enum PickerArrowKey {
    enum Direction { case up, down }

    static func move(_ direction: Direction, selection currentID: UUID?, in entries: [ClipboardEntry]) -> UUID? {
        guard !entries.isEmpty else { return nil }
        guard let currentID, let currentIndex = entries.firstIndex(where: { $0.id == currentID }) else {
            return entries.first?.id
        }

        switch direction {
        case .up:
            return entries[max(currentIndex - 1, 0)].id
        case .down:
            return entries[min(currentIndex + 1, entries.count - 1)].id
        }
    }
}
