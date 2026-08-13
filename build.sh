#!/bin/bash
# Builds LangKeys.app. Pass --install to also copy it into /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/LangKeys.app"

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
