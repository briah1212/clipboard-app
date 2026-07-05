#!/bin/bash
# Builds the app and signs it with the local "ClipboardManager Local
# Signing" identity (created once via Certificate Assistant). Signing with
# a stable identity is what lets macOS remember "Always Allow" for the
# Keychain-stored Anthropic API key across rebuilds - an unsigned/ad-hoc
# binary looks like a "new" app to Keychain every time and reprompts.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build "$@"

BINARY="$(swift build --show-bin-path)/ClipboardManager"
codesign --force --sign "ClipboardManager Local Signing" "$BINARY"
echo "Built and signed: $BINARY"
