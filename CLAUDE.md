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
- Test: `swift test` (no test target exists yet)

This is a Swift Package Manager executable, not an `.xcodeproj`. There is no
`Info.plist`; the app avoids a Dock icon by calling
`NSApp.setActivationPolicy(.accessory)` in `main.swift` instead of setting
`LSUIElement`.

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
- `HotkeyManager` - global keyboard shortcut registration; Carbon
  `RegisterEventHotKey` implementation is stubbed out (`start()`/`stop()`
  are TODOs).
- `PickerWindow` - the floating SwiftUI picker surface.
- `PasteService` - writes the selected entry to the pasteboard and
  simulates the paste keystroke.
- `MenuBarController` - `NSStatusItem` menu; the app's only other entry
  point into opening the picker besides the hotkey.

## Known gaps (intentionally deferred, not bugs)

- `HotkeyManager` does not yet register a real system hotkey.
- `ClipboardStore` only captures plain text (`NSPasteboard.string(forType: .string)`);
  images, files, and RTF are not captured.
- No persistence across app restarts - history is in-memory only.
