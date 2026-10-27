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

# Ad-hoc sign so macOS is happy to launch it locally.
codesign --force --sign - "$BUNDLE" 2>/dev/null || true

echo "Built ${BUNDLE}"
echo "Run: open ${BUNDLE}"
