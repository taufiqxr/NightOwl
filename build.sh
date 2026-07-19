#!/bin/bash
# NightOwl build script.
#
#   ./build.sh              build NightOwl.app into build/
#   ./build.sh --install    build + install to /Applications + (re)launch
#   ./build.sh --release    build + zip a shareable dist/NightOwl-<ver>.zip
#
# Requires the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build/NightOwl.app"

# App icon: generate once, then it's cached in Resources/
if [ ! -f Resources/AppIcon.icns ]; then
  echo "Generating app icon..."
  swift scripts/make-icon.swift /tmp/nightowl-icon-1024.png
  ICONSET=/tmp/NightOwl.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s /tmp/nightowl-icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d /tmp/nightowl-icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$ICONSET" /tmp/nightowl-icon-1024.png
fi

echo "Compiling..."
mkdir -p build
swiftc -O Sources/main.swift -o build/NightOwl

echo "Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp build/NightOwl "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns \
   Resources/nightowl-auto.sh \
   Resources/com.nightowl.auto.plist \
   "$APP/Contents/Resources/"
codesign --force --sign - "$APP" 2>/dev/null

echo "Built $APP (v$VERSION)"

if [ "${1:-}" = "--install" ]; then
  echo "Installing to /Applications..."
  pkill -f "NightOwl.app/Contents/MacOS/NightOwl" 2>/dev/null || true
  rm -rf "/Applications/NightOwl.app"
  cp -R "$APP" /Applications/
  open "/Applications/NightOwl.app"
  echo "NightOwl is running — look for 🦉 or 💤 in the menu bar."
elif [ "${1:-}" = "--release" ]; then
  mkdir -p dist
  ZIP="dist/NightOwl-${VERSION}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Shareable archive: $ZIP"
fi
