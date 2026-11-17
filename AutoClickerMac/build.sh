#!/bin/bash
# Build AutoClicker.app (universal: Apple Silicon + Intel)
# Yêu cầu: Xcode hoặc Command Line Tools (chạy: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="AutoClicker.app"
BIN="$APP/Contents/MacOS/AutoClicker"

rm -rf build "$APP"
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▶ Đang biên dịch (arm64)..."
swiftc -parse-as-library -O -target arm64-apple-macos13.0 AutoClicker.swift -o build/AutoClicker-arm64
echo "▶ Đang biên dịch (x86_64)..."
swiftc -parse-as-library -O -target x86_64-apple-macos13.0 AutoClicker.swift -o build/AutoClicker-x86_64

lipo -create build/AutoClicker-arm64 build/AutoClicker-x86_64 -output "$BIN"
cp Info.plist "$APP/Contents/Info.plist"

echo "▶ Ký ad-hoc..."
codesign --force --deep --sign - "$APP"

rm -rf build
echo "✅ Xong: $(pwd)/$APP"
echo "   Mở bằng: open \"$APP\"   (hoặc kéo vào thư mục Applications)"
