# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A personal macOS clipboard manager. It watches the system pasteboard, keeps a
local history of copied items, and lets the user summon a floating picker
window with a global hotkey to select and paste a past clipboard entry,
instead of only ever having access to the single most recent copy.

Single-laptop, no sync, no cloud. See `~/.claude/plans/zesty-cuddling-dragonfly.md`
for the original design plan and rationale.

## Commands

- Build: `swift build`
- Run: `swift run`
- Test: `swift test`
- Single test: `swift test --filter ClipboardManagerTests.HotkeyManagerTests`

This is a Swift Package Manager executable, not an `.xcodeproj`. There is no
`Info.plist`; the app avoids a Dock icon by calling
`NSApp.setActivationPolicy(.accessory)` in `main.swift` instead of setting
`LSUIElement`.

Deployment target is macOS 26 (`swift-tools-version: 6.2`, `.macOS(.v26)` in
Package.swift) so the picker can use the real Liquid Glass SwiftUI APIs
(`glassEffect(_:in:)`, the `Glass` type). This also puts the package in
Swift 6 language mode, so anything touching AppKit/SwiftUI
(`PickerWindow`, `MenuBarController`) is `@MainActor`-isolated; tests that
call into them need `@MainActor` too.

## Architecture

Entry point is `Sources/ClipboardManager/main.swift`, which creates an
`NSApplication`, sets the accessory activation policy, and installs
`MenuBarController`. Everything else is wired through that controller.

Data flow: `PasteboardWatcher` polls `NSPasteboard.general.changeCount` on a
timer (macOS has no push notification for clipboard changes) and appends new
text entries to `ClipboardStore`. `HotkeyManager` listens for a global
shortcut and, when pressed, tells `MenuBarController` to open
`PickerWindow`, which reads the current entries out of the store and shows
them in a borderless floating `NSPanel`/SwiftUI list. Selecting an entry
calls `PasteService`, which writes it back onto the pasteboard and
synthesizes a Cmd+V key event via `CGEvent` to paste into whatever app had
focus before the picker opened (requires Accessibility permission).

Module responsibilities (all under `Sources/ClipboardManager/`):

- `PasteboardWatcher` - polling + capture into `ClipboardStore`.
- `ClipboardStore` - in-memory history (capped at 200 entries), no
  persistence yet.
- `HotkeyManager` - registers the global Cmd+Shift+V shortcut via Carbon's
  `RegisterEventHotKey`/`InstallEventHandler`. The C event handler forwards
  into `hotKeyPressed(id:)`, which is exposed internally so tests can drive
  the dispatch logic without depending on real OS key delivery.
- `PickerWindow` - the floating SwiftUI picker surface: a borderless,
  non-activating `NSPanel` styled with Liquid Glass (`.glassEffect`), a
  close button, click-away-to-dismiss (observes
  `NSWindow.didResignKeyNotification`), Escape to close
  (`.onExitCommand`), and arrow-key/Enter navigation via `List(selection:)`.
  Calls `NSApp.activate(ignoringOtherApps: true)` before showing itself -
  without that, an `.accessory` app's panel can appear but never gets a
  real WindowServer handoff, so it renders blank and swallows all input.
- `PasteService` - writes the selected entry to the pasteboard and
  simulates the paste keystroke.
- `MenuBarController` - `NSStatusItem` menu; the app's only other entry
  point into opening the picker besides the hotkey.

## Testing approach

Tests live in `Tests/ClipboardManagerTests/` and favor vertical slices over
isolated unit mocks: `CopyPickPasteFlowTests` drives the real
`NSPasteboard.general` through copy -> watcher poll -> hotkey trigger ->
paste, and asserts on the pasteboard's actual contents at the end. This
works in CI because macOS GitHub Actions runners have a real pasteboard and
Carbon Event Manager available; the one seam that's mocked is the Cmd+V
keystroke synthesis (`PasteService.paste(_:simulateKeystroke:)`), since
injecting real key events into whatever app has focus would be unsafe to
run unattended.

## Known gaps (intentionally deferred, not bugs)

- `ClipboardStore` only captures plain text (`NSPasteboard.string(forType: .string)`);
  images, files, and RTF are not captured.
- No persistence across app restarts - history is in-memory only.
