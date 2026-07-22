#!/bin/bash
# One-time setup: trust Lingo's self-signed code-signing certificate so that
# the Accessibility permission persists across rebuilds. Requires an admin
# password (macOS gates trust changes behind authentication).
set -e
CERT="$HOME/Library/Application Support/Lingo/cert.pem"
if [ ! -f "$CERT" ]; then echo "Certificate not found at $CERT"; exit 1; fi
echo "Trusting Lingo's code-signing certificate (you'll be asked for your password)…"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$CERT"
echo "✓ Done. Now run 'make install' to sign with the stable identity, then grant Accessibility once."
