#!/bin/bash
# Builds "ScreenBridge Display", the app that turns a Mac (e.g. an iMac)
# into an extra screen for another Mac. Needs Xcode, but never opens it.
#
# Usage:
#   ./scripts/install-mac-display.sh          build and install on THIS Mac
#   ./scripts/install-mac-display.sh --zip    build here, make a .zip on the
#                                             Desktop to copy to the iMac
#                                             (the iMac then needs no Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Generating the Xcode project…"
xcodegen generate --quiet

echo "▸ Building ScreenBridge Display (Release, Intel + Apple silicon)…"
xcodebuild -project ScreenBridge.xcodeproj -scheme ScreenBridgeDisplay-macOS -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  -allowProvisioningUpdates -quiet build

APP="build/Build/Products/Release/ScreenBridge Display.app"

if [[ "${1:-}" == "--zip" ]]; then
  ZIP="$HOME/Desktop/ScreenBridge-Display.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "✓ Done: $ZIP"
  echo "  Send it to the iMac (AirDrop or USB drive), then on the iMac run:"
  echo "    cd ~/Downloads && unzip -o ScreenBridge-Display.zip && \\"
  echo "    rm -rf \"/Applications/ScreenBridge Display.app\" && \\"
  echo "    mv \"ScreenBridge Display.app\" /Applications/ && \\"
  echo "    xattr -dr com.apple.quarantine \"/Applications/ScreenBridge Display.app\" && \\"
  echo "    open \"/Applications/ScreenBridge Display.app\""
  exit 0
fi

echo "▸ Installing into /Applications…"
pkill -x "ScreenBridge Display" 2>/dev/null || true
rm -rf "/Applications/ScreenBridge Display.app"
cp -R "$APP" /Applications/
open "/Applications/ScreenBridge Display.app"
echo "✓ Done. ScreenBridge Display is in /Applications and running."
