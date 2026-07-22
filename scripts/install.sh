#!/bin/bash
# Lingo installer — downloads the latest release and installs it to /Applications.
# macOS only.
set -euo pipefail

REPO="JasonSung0724/Lingo-ai-translator"
APP="/Applications/Lingo.app"

if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Lingo is a macOS-only app." >&2
    exit 1
fi

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 15 ]; then
    echo "❌ Lingo requires macOS 15 (Sequoia) or later. You have $(sw_vers -productVersion)." >&2
    exit 1
fi

if [ ! -w /Applications ]; then
    echo "❌ /Applications is not writable by this user. Re-run from an administrator account." >&2
    exit 1
fi

echo "▸ Finding the latest release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -oE 'https://[^"]*Lingo\.zip' | head -1)"
if [ -z "${URL:-}" ]; then
    echo "❌ Could not find a release (network problem or GitHub API rate limit)." >&2
    echo "   Download manually: https://github.com/$REPO/releases/latest" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "▸ Downloading…"
curl -fsSL "$URL" -o "$TMP/Lingo.zip"

# Extract and verify BEFORE touching any existing install.
ditto -x -k "$TMP/Lingo.zip" "$TMP/extract"
if [ ! -x "$TMP/extract/Lingo.app/Contents/MacOS/Lingo" ]; then
    echo "❌ Downloaded archive looks corrupt — existing install left untouched." >&2
    exit 1
fi

ARCH="$(uname -m)"
if ! lipo -archs "$TMP/extract/Lingo.app/Contents/MacOS/Lingo" 2>/dev/null | grep -q "$ARCH"; then
    echo "❌ This build doesn't include your CPU ($ARCH). Build from source: https://github.com/$REPO" >&2
    exit 1
fi

echo "▸ Installing to $APP…"
rm -rf "$APP"
ditto "$TMP/extract/Lingo.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "✓ Lingo installed — look for the icon in your menu bar."
