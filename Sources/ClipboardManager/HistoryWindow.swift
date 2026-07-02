import SwiftUI
import AppKit

@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()

    /// Exposed internally (not private) so tests can drive the real
    /// AppKit close path (`performClose`) the same way clicking the native
    /// red button does, rather than only through our own `hide()`.
    ///
    /// This window is created once and then never deallocated for the rest
    /// of the process's life - repeated EXC_BAD_ACCESS crashes during
    /// NSWindow teardown on this macOS build (confirmed via two different
    /// signatures in ~/Library/Logs/DiagnosticReports) persisted even after
    /// disabling the close animation and deferring our own reference
    /// release, so the reliable fix is to never let it deallocate at all:
    /// `hide()` orders it out instead of closing it, and `windowShouldClose`
    /// redirects the native close button/Cmd+W into the same `hide()`
    /// rather than letting AppKit actually close (and eventually dealloc)
    /// the window.
    private(set) var window: NSWindow?
    private var restorer = PreviousAppRestorer()

    var isShowingWindow: Bool { window?.isVisible ?? false }

    /// `previouslyActiveApp`, when supplied, is used instead of reading
    /// `NSWorkspace.shared.frontmostApplication` live - needed when this is
    /// opened mid-transition from `PickerWindow` (pressing "O"), at which
    /// point ClipboardManager itself is already frontmost, so a live read
    /// would wrongly remember ourselves instead of whichever external app
    /// was active before the compact popup ever appeared.
    func show(history: ClipboardStore, previouslyActiveApp: NSRunningApplication? = nil) {
        if let previouslyActiveApp {
            restorer.capture(previouslyActiveApp)
        } else {
            restorer.capture()
        }

        let view = HistoryView(
            store: history,
            onSelect: { [weak self] entry in
                self?.hide(thenPaste: entry)
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        if let window, let hostingView = window.contentView as? NSHostingView<HistoryView> {
            hostingView.rootView = view
        } else {
            let contentRect = NSRect(x: 0, y: 0, width: 720, height: 470)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = contentRect

            let newWindow = NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Clipboard History"
            newWindow.contentView = hostingView
            newWindow.minSize = NSSize(width: 560, height: 360)
            newWindow.animationBehavior = .none
            // Belt-and-suspenders alongside never actually calling close():
            // even if something forces a real close, don't let AppKit
            // deallocate the window as a result.
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            window = newWindow
        }

        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        hide(thenPaste: nil)
    }

    private func hide(thenPaste entry: ClipboardEntry?) {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
        restorer.restore(thenPaste: entry)
    }

    /// Intercepts the native red close button and Cmd+W (both route
    /// through `performClose`, which consults this) and redirects into our
    /// own `hide()` instead of letting the window actually close.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

private struct HistoryView: View {
    let store: ClipboardStore
    let onSelect: (ClipboardEntry) -> Void
    let onClose: () -> Void

    @State private var searchQuery = ""
    @State private var filterKind: HistoryFilterKind = .all
    @State private var selection: UUID?
    @State private var hoveredID: UUID?
    @FocusState private var isFocused: Bool

    private var filteredEntries: [ClipboardEntry] {
        HistoryFilter.apply(entries: store.entries, query: searchQuery, kind: filterKind)
    }

    private var groupedEntries: [(sectionTitle: String, entries: [ClipboardEntry])] {
        HistoryGrouping.grouped(entries: filteredEntries, now: Date())
    }

    private var selectedEntry: ClipboardEntry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                list
                    .frame(width: 300)
                Divider().opacity(0.5)
                preview
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            selection = filteredEntries.first?.id
            isFocused = true
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.return) {
            guard let selectedEntry else { return .ignored }
            onSelect(selectedEntry)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = PickerArrowKey.move(.up, selection: selection, in: filteredEntries)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selection = PickerArrowKey.move(.down, selection: selection, in: filteredEntries)
            return .handled
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            filterControl
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var filterControl: some View {
        HStack(spacing: 2) {
            filterButton(.all, title: "All")
            filterButton(.links, title: "Links")
            filterButton(.code, title: "Code")
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    private func filterButton(_ kind: HistoryFilterKind, title: String) -> some View {
        let isActive = filterKind == kind
        return Text(title)
            .font(.system(size: 12))
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                isActive ? Color(nsColor: .windowBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .shadow(color: isActive ? .black.opacity(0.12) : .clear, radius: 1, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { filterKind = kind }
    }

    private var list: some View {
        Group {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(groupedEntries, id: \.sectionTitle) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                listRow(entry)
                            }
                        } header: {
                            Text(group.sectionTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .textCase(.uppercase)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(8)
    }

    private func listRow(_ entry: ClipboardEntry) -> some View {
        let isSelected = selection == entry.id
        return HStack(spacing: 10) {
            kindIcon(for: entry, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(subtitle(for: entry))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? DesignColors.accentBlue : (hoveredID == entry.id ? Color.primary.opacity(0.045) : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in hoveredID = isHovering ? entry.id : nil }
        .onTapGesture(count: 2) { onSelect(entry) }
        .onTapGesture(count: 1) { selection = entry.id }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func kindIcon(for entry: ClipboardEntry, isSelected: Bool) -> some View {
        let kind = ClipboardEntryKind.classify(entry.text)
        return RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.06))
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(searchQuery.isEmpty && filterKind == .all ? "No clipboard history yet." : "No matches.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.8))

            if let entry = selectedEntry {
                ScrollView {
                    Text(entry.text)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(16)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Text(footerCaption(for: entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete") {
                        store.remove(id: entry.id)
                        selection = filteredEntries.first?.id
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

                    Button("Paste") { onSelect(entry) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(DesignColors.accentBlue, in: RoundedRectangle(cornerRadius: 7))
                }
            } else {
                Spacer(minLength: 0)
                Text("Select an item to preview")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func footerCaption(for entry: ClipboardEntry) -> String {
        let count = entry.text.count
        let unit = count == 1 ? "character" : "characters"
        if let app = entry.sourceAppName {
            return "\(count) \(unit) · \(app)"
        }
        return "\(count) \(unit)"
    }

    private func subtitle(for entry: ClipboardEntry) -> String {
        let time = Self.relativeFormatter.localizedString(for: entry.timestamp, relativeTo: Date())
        if let app = entry.sourceAppName {
            return "\(app) · \(time)"
        }
        return time
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

enum HistoryFilterKind: CaseIterable {
    case all, links, code
}

/// Heuristic content classification for the All/Links/Code filter. There's
/// no real per-type capture (the store only ever holds plain text), so this
/// is a best-effort read of the text itself - not expected to be perfect,
/// just useful enough to make the filter meaningful.
enum ClipboardEntryKind {
    case text, link, code

    static func classify(_ text: String) -> ClipboardEntryKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        if isLink(trimmed) { return .link }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Treats text as a link only when a detected URL spans (almost) the
    /// whole string, not when a URL merely appears somewhere inside a
    /// longer sentence.
    private static func isLink(_ text: String) -> Bool {
        guard let detector = linkDetector else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range) else { return false }
        return Double(match.range.length) >= Double(text.utf16.count) * 0.9
    }

    private static let codeKeywordPattern = try? NSRegularExpression(
        pattern: #"\b(func|class|struct|enum|def|import|const|let|var|public|private|return)\b"#
    )

    private static func looksLikeCode(_ text: String) -> Bool {
        if text.contains("{") && text.contains("}") { return true }
        if text.contains(";") && (text.contains("(") || text.contains("=")) { return true }
        guard let pattern = codeKeywordPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}

/// Pure search + kind filtering over the store's entries, kept separate
/// from the view so it's unit-testable without driving real SwiftUI state.
enum HistoryFilter {
    static func apply(entries: [ClipboardEntry], query: String, kind: HistoryFilterKind) -> [ClipboardEntry] {
        entries.filter { matchesKind($0, kind: kind) && matchesQuery($0, query: query) }
    }

    private static func matchesKind(_ entry: ClipboardEntry, kind: HistoryFilterKind) -> Bool {
        switch kind {
        case .all: return true
        case .links: return ClipboardEntryKind.classify(entry.text) == .link
        case .code: return ClipboardEntryKind.classify(entry.text) == .code
        }
    }

    private static func matchesQuery(_ entry: ClipboardEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return entry.text.range(of: query, options: .caseInsensitive) != nil
    }
}

/// Buckets entries (assumed already newest-first, as `ClipboardStore`
/// always yields them) into day sections, kept separate from the view so
/// it's unit-testable with a fixed `now` rather than `Date()`.
enum HistoryGrouping {
    static func grouped(
        entries: [ClipboardEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [(sectionTitle: String, entries: [ClipboardEntry])] {
        var order: [String] = []
        var buckets: [String: [ClipboardEntry]] = [:]

        for entry in entries {
            let title = sectionTitle(for: entry.timestamp, now: now, calendar: calendar)
            if buckets[title] == nil {
                buckets[title] = []
                order.append(title)
            }
            buckets[title]?.append(entry)
        }

        return order.map { (sectionTitle: $0, entries: buckets[$0] ?? []) }
    }

    private static func sectionTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
