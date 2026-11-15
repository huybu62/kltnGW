#!/bin/bash
# Builds the iPad (Display) app in Release and installs it on a connected iPad.
# Needs Xcode installed (signed in with your Apple ID), but never opens it.
# The iPad must be plugged in (or paired over Wi-Fi in Xcode once) and unlocked.
# With a free Apple ID the app expires after 7 days: just run this again.
# Usage:  ./scripts/install-ipad.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Generating the Xcode project…"
xcodegen generate --quiet

echo "▸ Building ScreenBridge for iPad (Release)…"
xcodebuild -project ScreenBridge.xcodeproj -scheme ScreenBridgeDisplay-iOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  -allowProvisioningUpdates -quiet build

APP="build/Build/Products/Release-iphoneos/ScreenBridge.app"
DEVICES_JSON="$(mktemp)"
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

# First iPad/iPhone that is reachable right now.
DEVICE="$(/usr/bin/python3 - "$DEVICES_JSON" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and conn.get("tunnelState") != "unavailable":
        print(d["identifier"])
        break
PY
)"
if [ -z "$DEVICE" ]; then
  echo "✗ No iPad found. Plug it in, unlock it, tap Trust if asked, then run this again."
  exit 1
fi

echo "▸ Installing on the iPad…"
xcrun devicectl device install app --device "$DEVICE" "$APP"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "✓ Done. ScreenBridge is installed on the iPad."
