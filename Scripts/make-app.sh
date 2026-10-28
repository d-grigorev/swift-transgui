#!/usr/bin/env bash
# Build SwiftTransGUI.app from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="SwiftTransGUI"
BUNDLE="build/${APP_NAME}.app"

swift build -c "$CONFIG"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp ".build/${CONFIG}/${APP_NAME}" "$BUNDLE/Contents/MacOS/${APP_NAME}"
cp "Scripts/Info.plist" "$BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Stable signing identity: ad-hoc (-) signatures change their CDHash on
# every build, so the Keychain item's ACL can never match and every
# "Always Allow" would be re-requested after each rebuild. Sign with the
# first valid codesigning identity on the machine (e.g. an Apple
# Development certificate) whose designated requirement stays stable across
# builds — one "Always Allow" then covers all future builds. Falls back to
# ad-hoc signing when no identity exists.
IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -n 's/^[[:space:]]*[0-9]*) [0-9A-F]* "\(.*\)".*/\1/p' | head -1)"
if [ -n "$IDENTITY" ]; then
  echo "signing with: $IDENTITY"
  codesign --force --sign "$IDENTITY" "$BUNDLE"
else
  echo "no codesigning identity found — ad-hoc signing (Keychain prompts may recur)"
  codesign --force --sign - "$BUNDLE" 2>/dev/null || true
fi

echo "Built ${BUNDLE}"
echo "Run: open ${BUNDLE}"
