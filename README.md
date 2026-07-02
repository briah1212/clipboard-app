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
- Select an entry to paste it into whatever app currently has focus.

## Requirements

- macOS 13 (Ventura) or later.
- Xcode 15.3+ / Swift 5.10+ to build from source.
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
3. Click the entry you want.
4. It's written back onto the pasteboard and pasted into the app that had focus.

You can also click the menu bar icon and choose "Open History" to get the same picker without the hotkey.

## Development

```sh
swift test
```

Tests favor exercising the real flow (copy, poll, hotkey trigger, paste) against the actual `NSPasteboard` rather than mocking each piece in isolation.
See `CLAUDE.md` for the full architecture breakdown and known gaps.

CI runs `swift build` and `swift test` on every push and pull request to `main` (`.github/workflows/ci.yml`).
