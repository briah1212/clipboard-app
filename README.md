# Clipboard Manager

A personal macOS clipboard manager.
It watches the system pasteboard, keeps a local history of everything you copy, and lets you summon a floating picker window with a global hotkey to pick and paste any past entry.
No more only having access to the single most recent copy.

This is a single-laptop personal tool.
There is no cloud sync and no account system.

## Features

- Runs quietly in the menu bar, no Dock icon.
- Watches the pasteboard in the background and captures every text copy into a local history.
- Press `Cmd+Shift+V` anywhere to open a floating picker with your clipboard history.
- Rows are numbered 1-9; press that number to paste the corresponding entry into whatever app currently has focus and close the picker.
  1 is the most recent copy, 2 the one before that, and so on.

## Requirements

- macOS 15 (Sequoia) or later to build and run; macOS 26 (Tahoe) for the Liquid Glass picker styling (it falls back to a plain material on older macOS).
- Xcode 26+ / Swift 6.2+ to build from source.
- Accessibility permission, so the app can synthesize the paste keystroke into other apps.
  You'll be prompted for this the first time you paste from the picker.

## Build and run

```sh
swift build
swift run
```

The app has no Dock icon; look for the clipboard icon in the menu bar after launching.

## Usage

1. Copy a few things as you normally would, anywhere on your Mac.
2. Press `Cmd+Shift+V` to open the picker.
3. Press the number next to the entry you want (1 is the most recent copy).
4. It's written back onto the pasteboard and pasted into the app that had focus, and the picker closes.

You can also click a row, or use the arrow keys and Enter, though number keys are the most reliable way to select an entry in a borderless floating panel like this one. Press Esc, click the close button, or click outside the picker to dismiss it without pasting.

You can also click the menu bar icon and choose "Open History" to get the same picker without the hotkey.

## Development

```sh
swift test
```

Tests favor exercising the real flow (copy, poll, hotkey trigger, paste) against the actual `NSPasteboard` rather than mocking each piece in isolation.
See `CLAUDE.md` for the full architecture breakdown and known gaps.

CI runs `swift build` and `swift test` on every push and pull request to `main` (`.github/workflows/ci.yml`).
