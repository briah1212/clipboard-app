#!/bin/bash
# Builds a release ClipboardManager.app, signs it with the local
# "ClipboardManager Local Signing" identity, installs it to
# ~/Applications, and (re)launches it.
#
# Running the app as a signed bundle (not `swift run` from a terminal) is
# what makes the one-time Accessibility grant attach to the app itself and
# survive rebuilds, and what lets "Launch at Login" (SMAppService) work.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClipboardManager"
IDENTITY="ClipboardManager Local Signing"
INSTALL_DIR="$HOME/Applications"
STAGED_APP=".build/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

swift build -c release
BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/MacOS"
cp Packaging/Info.plist "$STAGED_APP/Contents/Info.plist"
cp "$BINARY" "$STAGED_APP/Contents/MacOS/$APP_NAME"
codesign --force --sign "$IDENTITY" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

# Quit any running copy (installed bundle or a `swift run` binary) before
# replacing it, so there is never more than one watcher or hotkey owner.
pkill -x -U "$UID" "$APP_NAME" || true
for _ in {1..50}; do
    pgrep -x -U "$UID" "$APP_NAME" >/dev/null || break
    sleep 0.1
done
if pgrep -x -U "$UID" "$APP_NAME" >/dev/null; then
    echo "error: $APP_NAME is still running; quit it and rerun." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$STAGED_APP" "$INSTALLED_APP"
open "$INSTALLED_APP"
echo "Installed and launched: $INSTALLED_APP"
