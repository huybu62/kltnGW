#!/bin/bash
# Builds the Mac (Host) app in Release and installs it into /Applications.
# Needs Xcode installed (signed in with your Apple ID), but never opens it.
# Usage:  ./scripts/install-mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Generating the Xcode project…"
xcodegen generate --quiet

echo "▸ Building ScreenBridge (Release, Intel + Apple silicon)…"
xcodebuild -project ScreenBridge.xcodeproj -scheme ScreenBridgeHost -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  -allowProvisioningUpdates -quiet build

APP="build/Build/Products/Release/ScreenBridge.app"
echo "▸ Installing into /Applications…"
pkill -x ScreenBridge 2>/dev/null || true
rm -rf "/Applications/ScreenBridge.app"
cp -R "$APP" /Applications/

open /Applications/ScreenBridge.app
echo "✓ Done. ScreenBridge is in /Applications and running (menu bar)."
echo "  If touch control stops working, turn ScreenBridge off and on again in"
echo "  System Settings → Privacy & Security → Accessibility."
