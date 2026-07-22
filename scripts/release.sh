#!/bin/bash
# Build distributable Lingo.zip + Lingo.dmg for a GitHub Release.
# Requires a universal (arm64 + x86_64) binary; set UNIVERSAL=0 to override for
# local experiments (never for a real release).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UNIVERSAL="${UNIVERSAL:-1}" bash scripts/build.sh release

if [ "${UNIVERSAL:-1}" = "1" ]; then
    ARCHS="$(lipo -archs Lingo.app/Contents/MacOS/Lingo)"
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) echo "▸ Verified universal binary ($ARCHS)";;
        *) echo "❌ Release build must be universal, got: $ARCHS" >&2; exit 1;;
    esac
fi

mkdir -p dist
rm -f dist/Lingo.zip dist/Lingo.dmg
# ditto preserves the .app bundle correctly for macOS.
ditto -c -k --keepParent Lingo.app dist/Lingo.zip
# DMG with a drag-to-Applications layout for GUI-only installs.
STAGE="$(mktemp -d)"
cp -R Lingo.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lingo" -srcfolder "$STAGE" -ov -format UDZO dist/Lingo.dmg >/dev/null
rm -rf "$STAGE" Lingo.app
echo "✓ dist/Lingo.zip + dist/Lingo.dmg ready — attach them to a GitHub Release."
echo "  Note: the app is not notarized. First launch needs System Settings →"
echo "  Privacy & Security → Open Anyway (the installer script avoids this)."
echo "  CI signs with the stable 'Lingo Self-Signed' identity so TCC grants persist."
