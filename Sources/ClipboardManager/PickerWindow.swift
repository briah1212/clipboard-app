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
    private var restorer = PreviousAppRestorer()

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
        restorer.capture()

        let view = PickerView(
            entries: history.entries,
            onSelect: { [weak self] entry in
                self?.hide(thenPaste: entry, store: history)
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onOpenFullHistory: { [weak self] in
                guard let self else { return }
                // Close the popup without restoring the app that was
                // active before Cmd+Shift+V - we're handing off to our own
                // full history window, not actually leaving the app.
                // Restoring here would asynchronously reactivate that
                // external app at the same time HistoryWindow activates
                // itself, and the two races unpredictably - occasionally
                // leaving the external app on top and the history window
                // hidden behind it.
                let originalApp = self.restorer.previouslyActiveApp
                self.hide(thenPaste: nil, store: nil, restorePreviousApp: false)
                HistoryWindow.shared.show(history: history, previouslyActiveApp: originalApp)
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
        hide(thenPaste: nil, store: nil)
    }

    private func hide(thenPaste entry: ClipboardEntry?, store: ClipboardStore?, restorePreviousApp: Bool = true) {
        guard let panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        panel.close()
        self.panel = nil

        if restorePreviousApp {
            restorer.restore(thenPaste: entry, store: store)
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
    let onOpenFullHistory: () -> Void

    @State private var selection: UUID?
    @State private var hoveredID: UUID?
    @State private var isCloseHovered = false
    @FocusState private var isFocused: Bool
    @AppStorage(AppearancePreference.storageKey) private var prefersDarkMode: Bool = AppearancePreference.systemPrefersDark

    var body: some View {
        content
            .background(DesignColors.panelBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DesignColors.panelBorder))
            .preferredColorScheme(prefersDarkMode ? .dark : .light)
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
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { _ in
            onOpenFullHistory()
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
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 420, height: 360)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Circle()
                    .fill(Color.primary.opacity(isCloseHovered ? 0.11 : 0.06))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        // Deliberately not List(selection:) - on macOS that draws its own
        // native blue row-selection highlight underneath our custom row
        // background, showing as a stray highlight on top of our muted
        // accent tint. `selection` is tracked and styled entirely by hand
        // (row background + onTapGesture below), so List doesn't need to
        // know about it at all.
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(index: index, entry: entry)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(index: Int, entry: ClipboardEntry) -> some View {
        let isSelected = selection == entry.id
        return HStack(spacing: 8) {
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? DesignColors.accentBlue : .secondary)
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 3)
                    .background(
                        isSelected ? DesignColors.accentBlue.opacity(0.16) : Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            Text(entry.text)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelected {
                Text("Paste")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColors.accentBlue)
                Text("⏎")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColors.accentBlue)
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 3)
                    .background(DesignColors.accentBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? DesignColors.accentBlue.opacity(0.16)
                : (hoveredID == entry.id ? Color.primary.opacity(0.045) : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in hoveredID = isHovering ? entry.id : nil }
        .onTapGesture { onSelect(entry) }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No clipboard history yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if !entries.isEmpty {
                Text("↑↓ Navigate")
                Text("⏎ Paste")
            }
            Text("esc Close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 29)
        .frame(maxWidth: .infinity, alignment: .leading)
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
