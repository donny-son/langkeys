#!/bin/bash
# Builds LangKeys.app.
#   --install   also copy it into /Applications and launch it
#   --dmg       also package it as build/LangKeys.dmg
set -euo pipefail

cd "$(dirname "$0")"
APP="build/LangKeys.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"

echo "==> Building (universal release)"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/LangKeys "$APP/Contents/MacOS/LangKeys"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature with a stable identifier so macOS keeps the Accessibility grant
# across rebuilds instead of asking again every time.
codesign --force --sign - --identifier so.dou.langkeys "$APP"

if [[ "${1:-}" == "--dmg" ]]; then
  DMG="build/LangKeys-$VERSION.dmg"
  STAGE="build/dmg"
  echo "==> Packaging $DMG"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/LangKeys.app"
  # The Applications symlink is what makes the window a drag-to-install target.
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "LangKeys" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "==> Done: $DMG"
  echo "    Ad-hoc signed, so Gatekeeper will warn on other Macs. See README for notarizing."
  exit 0
fi

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x LangKeys || true
  rm -rf /Applications/LangKeys.app
  cp -R "$APP" /Applications/LangKeys.app
  open /Applications/LangKeys.app
  echo "==> Running from /Applications"
else
  echo "==> Done: $APP"
  echo "    Run ./build.sh --install to install and launch it."
fi
