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

`swift-tools-version` is 6.2, which puts the package in Swift 6 language
mode, so anything touching AppKit/SwiftUI (`PickerWindow`,
`MenuBarController`) is `@MainActor`-isolated; tests that call into them
need `@MainActor` too.

The deployment target is macOS 15 (`.macOS(.v15)` in Package.swift) even
though development happens on macOS 26, because GitHub Actions macOS
runners don't run macOS 26 as their host OS yet: a binary built against the
macOS 26 SDK with a macOS 26 minimum deployment target fails to even
`dlopen` there (`Symbol not found: ... built for macOS 26.0 which is newer
than running OS`). `PickerWindow`'s Liquid Glass styling
(`glassEffect(_:in:)`, the `Glass` type, macOS 26+ only) is therefore
gated behind `if #available(macOS 26, *)` with an `.ultraThinMaterial`
fallback for older runtimes - real glass on Brian's laptop, a plain
material anywhere the real API isn't loadable, including CI.

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
  non-activating `NSPanel` (`.nonactivatingPanel`) styled with Liquid Glass
  (`.glassEffect`), a close button, click-away-to-dismiss (observes
  `NSWindow.didResignKeyNotification`), and Escape to close
  (`.onExitCommand`). Getting digit keys to actually reach the picker took
  three separate fixes, verified with real synthetic keystrokes via
  `osascript`/System Events (not just visual inspection) since Accessibility
  permission for that only became available partway through debugging:
  1. Only the active application's key window receives real hardware key
     events on macOS, so `show()` calls `NSApp.activate(ignoringOtherApps: true)`.
     It records `NSWorkspace.shared.frontmostApplication` first; `hide()`
     reactivates that app immediately, and when closing because of a
     selection, waits ~50ms (activation is asynchronous) before calling
     `PasteService.paste` so the keystroke lands back in the field the
     user was originally in, not wherever this app happened to leave focus.
  2. SwiftUI's `.onKeyPress` only fires for a view holding *SwiftUI*
     focus, a separate concept from AppKit's key-window status that
     `makeKeyAndOrderFront` doesn't grant on its own. `PickerView` marks
     its root `.focusable()` and drives it with `@FocusState`, set `true`
     in `.onAppear`.
  3. The actual root cause of keys doing nothing even with both of the
     above in place: `NSPanel`'s default `canBecomeKey`/`canBecomeMain`
     return `false` for a borderless + `.nonactivatingPanel` window unless
     a subclass overrides them. Without the override,
     `makeKeyAndOrderFront` orders the panel to the front visually but it
     never actually becomes key, so it receives no keyboard events at all
     regardless of app activation or SwiftUI focus state - confirmed by
     logging `panel.isKeyWindow` before and after the fix. `KeyablePanel`
     is that subclass; `PickerWindowTests.testPanelCanBecomeKeyAndMain`
     locks it in.

  Rows are numbered 1-9, selectable by pressing that digit key (mapped to
  an entry by the standalone `PickerNumberKey.entry(forDigit:in:)`).
  Up/Down move `selection` via the standalone `PickerArrowKey.move(_:selection:in:)`,
  clamped at either end of the history, and Enter pastes whatever
  `selection` currently points at. Both helpers are kept separate from the
  view so they're unit-testable without driving real SwiftUI key events.
  Clicking a row also works. All three paths funnel through the same
  `onSelect` closure passed into `PickerView`.
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
