# Clipboard Manager

A personal macOS clipboard manager.
It watches the system pasteboard, keeps a local history of everything you copy, and lets you summon a floating picker window with a global hotkey to pick and paste any past entry.
No more only having access to the single most recent copy.

This is a single-laptop personal tool.
There is no cloud sync and no account system.

## Features

- Runs quietly in the menu bar, no Dock icon.
- Watches the pasteboard in the background and keeps the last 1,000 copies (text, images, file paths, and colors) in a local history that survives restarts.
- Skips copies that password managers mark as concealed or transient.
- Press `Cmd+Shift+V` anywhere to open a floating picker with your clipboard history.
- Rows are numbered 1-9; press that number to paste the corresponding entry into whatever app currently has focus and close the picker.
  1 is the most recent copy, 2 the one before that, and so on.
- Or use the Up/Down arrow keys to move the highlighted selection, then Enter to paste it.
- Press `O` in the picker to open the full history window: search, All/Links/Code filters, day-grouped sections, a preview pane, and Delete/Paste actions.
- Start a search with `/` in the history window for AI natural-language search (needs an Anthropic API key in the Keychain, see below).
- Launches at login (on by default for the installed app; toggle it in the menu bar menu or System Settings > General > Login Items).

## Requirements

- macOS 15 (Sequoia) or later to build and run; macOS 26 (Tahoe) for the Liquid Glass picker styling (it falls back to a plain material on older macOS).
- Xcode 26+ / Swift 6.2+ to build from source.
- Accessibility permission, so the app can synthesize the paste keystroke into other apps.
  The app asks for it on launch until it is granted.
- A code-signing identity named "ClipboardManager Local Signing" (a self-signed certificate made once in Keychain Access > Certificate Assistant > Create a Certificate, type Code Signing).
  A stable signature is what keeps the Accessibility and Keychain grants across rebuilds.

## Install

```sh
Scripts/install.sh
```

This builds a release `ClipboardManager.app`, signs it, installs it to `~/Applications`, and launches it, quitting any copy that is already running.
Rerun it after every change.

First run only:

1. On first launch macOS asks for Accessibility (needed to paste into other apps).
   Turn on ClipboardManager in System Settings > Privacy & Security > Accessibility.
   If `swift run` was used before, Terminal may be listed there instead; that grant does not cover the installed app.
2. Launch at Login turns itself on the first time the installed app runs.
   Turning it off later (menu bar menu or System Settings) sticks.

The app has no Dock icon; look for the clipboard icon in the menu bar.
On a crowded menu bar macOS hides icons behind the notch; Cmd-drag icons to rearrange them.
The hotkey works either way.

### AI search key (optional)

AI search reads an Anthropic API key from the Keychain, never from a file:

```sh
security add-generic-password -s com.clipboardmanager.anthropic-api-key -a ClipboardManager -w
```

The first AI search asks for Keychain access; choose "Always Allow".

## Run from source

```sh
swift run
```

Good for quick iteration, but the paste keystroke then runs under the terminal's Accessibility grant and "Launch at Login" is not offered.

## Usage

1. Copy a few things as you normally would, anywhere on your Mac.
2. Press `Cmd+Shift+V` to open the picker.
3. Either press the number next to the entry you want (1 is the most recent copy), or press Up/Down to move the highlight and Enter to paste it.
4. It's written back onto the pasteboard and pasted into the app that had focus, and the picker closes.

You can also click a row. Press Esc, click the close button, or click outside the picker to dismiss it without pasting.

You can also click the menu bar icon and choose "Open History" to get the same picker without the hotkey.

## Development

```sh
swift test
```

Tests favor exercising the real flow (copy, poll, hotkey trigger, paste) against the actual `NSPasteboard` rather than mocking each piece in isolation.
See `CLAUDE.md` for the full architecture breakdown and known gaps.

CI runs `swift build` and `swift test` on every push and pull request to `main` (`.github/workflows/ci.yml`).
