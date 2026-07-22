#!/bin/bash
# Build Lingo.app from the SwiftPM executable and assemble a macOS app bundle.
# UNIVERSAL=1 (used by release.sh/CI) builds arm64 + x86_64 separately and merges
# with lipo — a single multi-arch `swift build` silently fails on CI runners.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/Lingo.app"
cd "$ROOT"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "▸ Building ($CONFIG, arm64)…"
    swift build -c "$CONFIG" --arch arm64
    echo "▸ Building ($CONFIG, x86_64)…"
    swift build -c "$CONFIG" --arch x86_64
    BIN_ARM="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Lingo"
    BIN_X86="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/Lingo"
    mkdir -p "$ROOT/.build/universal"
    BIN="$ROOT/.build/universal/Lingo"
    lipo -create "$BIN_ARM" "$BIN_X86" -o "$BIN"
    echo "▸ Universal binary: $(lipo -archs "$BIN")"
else
    echo "▸ Building ($CONFIG, native arch)…"
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lingo"
fi

echo "▸ Assembling Lingo.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lingo"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Embed Sparkle.framework so the bundle is self-contained outside the build dir.
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Lingo" 2>/dev/null || true
else
    echo "⚠️  Sparkle.framework not found at $SPARKLE — updates won't work in this build." >&2
fi

IDENTITY="Lingo Self-Signed"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    SIGN_ID="$IDENTITY"
    echo "▸ Signing with '$IDENTITY' (stable — Accessibility grant persists)…"
else
    SIGN_ID="-"
    echo "▸ Ad-hoc signing (run scripts/trust-cert.sh once for a stable signature)…"
fi
# Sign the embedded framework first (covers its nested XPC services), then the app.
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign "$SIGN_ID" "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign "$SIGN_ID" "$APP"

echo "✓ Built $APP"
