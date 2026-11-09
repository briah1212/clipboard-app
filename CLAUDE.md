# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A personal macOS clipboard manager. It watches the system pasteboard, keeps a
persistent local history of copied items (text, images, file paths, and
colors), and lets the user summon a floating picker window with a global
hotkey to select and paste a past clipboard entry, instead of only ever
having access to the single most recent copy. Pressing "O" while the popup
is open promotes it to a full, resizable history window with search,
filtering, and AI-powered natural-language search.

Single-laptop, no sync, no cloud. See `~/.claude/plans/zesty-cuddling-dragonfly.md`
for the original design plan and rationale.

## Commands

- Build: `swift build`
- Build and code-sign with the stable local identity: `Scripts/build-and-sign.sh`
- Install for daily use (release `.app` in `~/Applications`, relaunched): `Scripts/install.sh`
- Run: `swift run`
- Test: `swift test`
- Single test: `swift test --filter ClipboardManagerTests.HotkeyManagerTests`

This is a Swift Package Manager executable, not an `.xcodeproj`. SwiftPM
doesn't produce an app bundle, so `Scripts/install.sh` wraps the release
binary in a minimal `ClipboardManager.app` using `Packaging/Info.plist`
(bundle id `com.clipboardmanager.app`, `LSUIElement`). The app also calls
`NSApp.setActivationPolicy(.accessory)` in `main.swift`, so `swift run`
has no Dock icon either. The bundle is what Accessibility (TCC) and
`SMAppService.mainApp` (the menu's "Launch at Login") key on; a bare
binary launched from a terminal inherits the terminal's Accessibility
grant instead, and can't register as a login item, so `MenuBarController`
only shows that item when running from an `.app`.

`swift-tools-version` is 6.2, which puts the package in Swift 6 language
mode, so anything touching AppKit/SwiftUI (`PickerWindow`, `HistoryWindow`,
`MenuBarController`) is `@MainActor`-isolated; tests that call into them
need `@MainActor` too. `ClipboardEntry` is a SwiftData `@Model` class (a
non-`Sendable` reference type), so anything that passes an entry across an
`async`/actor boundary (`PreviousAppRestorer`, `SemanticSearchClient`) is
also `@MainActor`-isolated rather than plain `Sendable`.

The deployment target is macOS 15 (`.macOS(.v15)` in Package.swift) even
though development happens on macOS 26, because GitHub Actions macOS
runners don't run macOS 26 as their host OS yet: a binary built against the
macOS 26 SDK with a macOS 26 minimum deployment target fails to even
`dlopen` there (`Symbol not found: ... built for macOS 26.0 which is newer
than running OS`).

### Code signing and the Anthropic API key

Semantic search (below) needs an Anthropic API key, stored in the Keychain
(service `com.clipboardmanager.anthropic-api-key`, account
`ClipboardManager`) - never in a file, never in source, never in
`UserDefaults`. Keychain access control is tied to the binary's code
signature; an unsigned/ad-hoc-signed debug build looks like a "new app"
to Keychain on every rebuild and reprompts for access every time. Building
via `Scripts/build-and-sign.sh` signs the binary with a stable local
identity ("ClipboardManager Local Signing", created once via Certificate
Assistant) so "Always Allow" persists across rebuilds.

## Architecture

Entry point is `Sources/ClipboardManager/main.swift`, which creates an
`NSApplication`, sets the accessory activation policy, and installs
`MenuBarController`. Everything else is wired through that controller.

Data flow: `PasteboardWatcher` polls `NSPasteboard.general.changeCount` on a
timer (macOS has no push notification for clipboard changes) and appends new
entries to `ClipboardStore`, which persists them via SwiftData.
`HotkeyManager` listens for a global shortcut and, when pressed, tells
`MenuBarController` to open `PickerWindow`, which reads the current entries
out of the store and shows them in a borderless floating `NSPanel`/SwiftUI
list. Pressing "O" there hands off to `HistoryWindow`, a titled, resizable
window with search, kind filtering, and AI semantic search over the same
store. Selecting an entry (from either window) calls `PasteService`, which
writes it back onto the pasteboard and synthesizes a Cmd+V key event via
`CGEvent` to paste into whatever app had focus before the window opened
(requires Accessibility permission).

Module responsibilities (all under `Sources/ClipboardManager/`):

- `PasteboardWatcher` - polling + capture into `ClipboardStore`. Each entry
  is a `ClipboardContent` case (`.text`, `.image`, `.fileURLs`, `.color`),
  stored as plain `Data`/`URL`/a `Sendable` `ColorComponents` struct rather
  than `NSImage`/`NSColor`. `pollNow()` checks pasteboard types in order of
  specificity per poll - file URLs, then color, then image, then plain text
  fallback - since a single copy often exposes more than one representation
  (a Finder file copy also exposes a plain-string path). Also captures
  `NSWorkspace.shared.frontmostApplication?.localizedName` as the entry's
  source app (imprecise by up to one poll interval, same category as the
  existing timestamp-isn't-exact-copy-moment behavior). Copies tagged with
  the `org.nspasteboard.*` concealed/transient/auto-generated convention
  (see nspasteboard.org - the marker password managers use) are skipped
  entirely, never entering history.
- `ClipboardStore` - `@MainActor @Observable`, backed by SwiftData
  (`ModelContainer`/`ModelContext`). In-memory `entries` array (capped at
  1000, oldest evicted first) mirrors what's persisted so the UI doesn't
  need to hit the store on every read. `ClipboardEntry.content` is stored
  as JSON-encoded `Data` behind a computed property (rather than a native
  SwiftData enum-with-associated-values) to avoid relying on uncertain
  SwiftData support for that shape. History lives at
  `~/Library/Application Support/ClipboardManager/History.sqlite`; test
  runs (detected via `NSClassFromString("XCTestCase") != nil`) get a fresh
  temp-file-backed container per instance instead - `isStoredInMemoryOnly`
  was tried first but was found to pool state across distinct containers
  in the same process, leaking entries between unrelated tests.
- `HotkeyManager` - registers the global Cmd+Shift+V shortcut via Carbon's
  `RegisterEventHotKey`/`InstallEventHandler`. The C event handler forwards
  into `hotKeyPressed(id:)`, which is exposed internally so tests can drive
  the dispatch logic without depending on real OS key delivery.
- `PreviousAppRestorer` - shared by `PickerWindow` and `HistoryWindow`:
  captures whichever app was frontmost before the window activated itself,
  and hands focus back to it on close, waiting ~50ms (activation is async)
  before calling `PasteService.paste` when a selection was made, so the
  keystroke lands back in the field the user was originally in.
- `PickerWindow` - the floating SwiftUI popup surface: a borderless,
  non-activating `NSPanel` (`.nonactivatingPanel`), Raycast-style flat
  styling (`DesignColors`), a custom close button, click-away-to-dismiss
  (observes `NSWindow.didResignKeyNotification`), and Escape to close
  (`.onExitCommand`). Getting digit keys to actually reach the picker took
  three separate fixes, verified with real synthetic keystrokes via
  `osascript`/System Events (not just visual inspection):
  1. Only the active application's key window receives real hardware key
     events on macOS, so `show()` calls `NSApp.activate(ignoringOtherApps: true)`,
     with `PreviousAppRestorer` remembering who was frontmost first so
     `hide()` can hand focus back immediately.
  2. SwiftUI's `.onKeyPress` only fires for a view holding *SwiftUI*
     focus, a separate concept from AppKit's key-window status that
     `makeKeyAndOrderFront` doesn't grant on its own. `PickerView` marks
     its root `.focusable()` and drives it with `@FocusState`, set `true`
     in `.onAppear`.
  3. The actual root cause of keys doing nothing even with both of the
     above in place: `NSPanel`'s default `canBecomeKey`/`canBecomeMain`
     return `false` for a borderless + `.nonactivatingPanel` window unless
     a subclass overrides them. `KeyablePanel` is that subclass;
     `PickerWindowTests.testPanelCanBecomeKeyAndMain` locks it in.

  Rows are numbered 1-9, selectable by pressing that digit key (mapped to
  an entry by the standalone `PickerNumberKey.entry(forDigit:in:)`).
  Up/Down move `selection` via the standalone `PickerArrowKey.move(_:selection:in:)`,
  clamped at either end of the history, and Enter pastes whatever
  `selection` currently points at. Pressing "o"/"O" calls
  `onOpenFullHistory`, which closes the popup *without* restoring the
  previously-active app (that handoff would race against `HistoryWindow`
  activating itself) and opens `HistoryWindow` instead, passing along the
  app it had already captured. Row content branches on the entry's
  `ClipboardContent` kind: plain text, a file icon + filename(s), an image
  thumbnail, or a color swatch + hex string. Deliberately not
  `List(selection:)` - that draws a native blue highlight underneath the
  custom row background; selection is tracked and styled entirely by hand.
- `HistoryWindow` - the full-history surface: a real titled, resizable
  `NSWindow` (not a panel), built once and never deallocated for the
  process's lifetime (`hide()` calls `orderOut`, never `close()`) - two
  distinct `EXC_BAD_ACCESS` crash signatures were seen during NSWindow
  teardown on this macOS build, and never letting the window deallocate at
  all was the reliable fix. `windowShouldClose` redirects the native red
  close button/Cmd+W into `hide()` rather than letting AppKit actually
  close it. Unlike the popup, it does *not* close on
  `didResignKeyNotification` - Cmd-Tab or Spotlight shouldn't make a
  titled window vanish. Search (substring, case-insensitive) and an
  All/Links/Code filter run through the pure, unit-tested `HistoryFilter`;
  entries are grouped into Today/Yesterday/dated sections by the pure
  `HistoryGrouping`; content-kind classification (including the
  text/link/code heuristic) is `ClipboardEntryKind.classify(_:)`. Arrow-key
  navigation reuses `PickerArrowKey.move` against the filtered list, so a
  selection that drops out of the current filter snaps to the top rather
  than going stale. The preview pane renders per-kind (monospaced text,
  image, file list with Finder icons, color swatch + hex) with Delete
  (`store.remove(id:)`) and Paste actions.

  A leading "/" in the search field switches it into AI semantic search
  (see `SemanticSearchService` below) instead of plain substring matching;
  results replace the day-grouped sections with a single relevance-ordered
  "Results" section, and fall back to a plain substring search over the
  post-slash text if the API call fails (missing/invalid key, network
  error) so the field is never a dead end. Enter is handled directly in
  the root `.onKeyPress(.return)` rather than via `TextField`'s
  `.onSubmit`, which did not reliably pre-empt the root handler while the
  field held focus - without this check, Enter always fell through to
  "paste the previously selected entry" even while typing an AI query.
- `SemanticSearchService` - ties together a local pre-filter and the
  network client, with an in-session cache keyed on (query, candidate ids)
  so retyping/resubmitting an identical query doesn't re-spend tokens.
  `SemanticSearchCandidates.select` scores and shortlists (default limit
  30) candidate entries by keyword overlap with the query *before* any
  network call happens - this is what keeps the full clipboard history
  from ever being shipped to the API regardless of how large it grows.
  `AnthropicSemanticSearchClient` calls the Messages API
  (`claude-haiku-4-5-20251001`, chosen for cost/speed) with only the
  shortlist - each entry truncated to a 150-character preview, not its
  full text - and forces the reply through a single `return_matches` tool
  call so the response is a tiny, reliably-parseable id list rather than
  free-form prose. Returned ids are filtered against the actual candidate
  set before use, so a malformed/hallucinated id can't reach the UI as a
  silent no-op lookup. `SemanticSearchClient` is the protocol seam tests
  substitute a fake for, matching how `PasteService`'s keystroke synthesis
  is the only mocked seam elsewhere in this codebase.
- `KeychainStore` - the only place the Anthropic API key is read from;
  `SecItemCopyMatching` blocks its calling thread until the OS's Keychain
  authorization dialog (if one is needed) is dismissed, so the lookup runs
  in a `Task.detached` rather than synchronously on the main actor - doing
  it synchronously previously froze the entire app, not just a small
  popup, for as long as that dialog sat unnoticed.
- `PasteService` - writes the selected entry back to the pasteboard,
  branching on its `ClipboardContent` kind (`writeObjects` for file URLs
  and colors - `setData` mis-pastes multi-file selections - `setData(forType:
  .png)` for images), then simulates the paste keystroke. Tells the store
  to suppress recapturing the entry it just wrote back.
- `MenuBarController` - `NSStatusItem` menu; the app's only other entry
  point into opening the picker besides the hotkey.
- `DesignColors` / `AppearancePreference` - brand-exact accent blue and
  flat panel background/border colors (Raycast-style, not Liquid Glass),
  each a light/dark-aware dynamic `NSColor`; a persisted (`@AppStorage`)
  light/dark toggle independent of the system appearance, surfaced as a
  button in both windows.

## Testing approach

Tests live in `Tests/ClipboardManagerTests/` and favor vertical slices over
isolated unit mocks: `CopyPickPasteFlowTests` drives the real
`NSPasteboard.general` through copy -> watcher poll -> hotkey trigger ->
paste, and asserts on the pasteboard's actual contents at the end. This
works in CI because macOS GitHub Actions runners have a real pasteboard and
Carbon Event Manager available; the seams that are mocked are
`PasteService.paste(_:simulateKeystroke:)` (injecting real key events into
whatever app has focus would be unsafe to run unattended) and
`SemanticSearchClient` (no real network calls in tests). Pure helpers
(`HistoryFilter`, `HistoryGrouping`, `ClipboardEntryKind`, `PickerNumberKey`,
`PickerArrowKey`, `SemanticSearchCandidates`) are colocated with the view
that uses them and built directly against `ClipboardEntry` fixtures rather
than through a transient `ClipboardStore` - a store going out of scope
deallocates its `ModelContext`, invalidating any `ClipboardEntry` objects
it produced.

## Known gaps (intentionally deferred, not bugs)

- Rich text/HTML is not captured as its own kind - a rich text copy falls
  through to the plain-string fallback in `PasteboardWatcher.pollNow()`.
