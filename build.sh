#!/bin/bash
# Builds LangKeys.app.
#   (no flag)   build/LangKeys.app, ad-hoc signed
#   --install   also copy it into /Applications and launch it
#   --dmg       also package it as build/LangKeys-<version>.dmg (ad-hoc, local use only)
#   --release   Developer ID sign + notarize + staple, ready to hand to other people
set -euo pipefail

cd "$(dirname "$0")"
APP="build/LangKeys.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
MODE="${1:-}"

echo "==> Building (universal release)"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/LangKeys "$APP/Contents/MacOS/LangKeys"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

make_dmg() {
  local dmg="$1" stage="build/dmg"
  rm -rf "$stage" "$dmg"
  mkdir -p "$stage"
  cp -R "$APP" "$stage/LangKeys.app"
  # The Applications symlink is what makes the window a drag-to-install target.
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "LangKeys" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
  rm -rf "$stage"
}

if [[ "$MODE" == "--release" ]]; then
  [[ -f .env ]] || { echo "❌ .env missing (see .env.example)"; exit 1; }
  set -a; source .env; set +a
  : "${APPLE_API_KEY:?not set in .env}" "${APPLE_API_KEY_ID:?not set in .env}"
  : "${APPLE_API_ISSUER:?not set in .env}" "${APPLE_TEAM_ID:?not set in .env}"

  # Pick the Developer ID cert by hash so a keychain with several identities is unambiguous.
  IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | grep "$APPLE_TEAM_ID" | head -1 | awk '{print $2}')"
  [[ -n "$IDENTITY" ]] || {
    echo "❌ No 'Developer ID Application' certificate for team $APPLE_TEAM_ID in the keychain."
    exit 1
  }

  # APPLE_API_KEY may be a path to the .p8 or the key itself; notarytool needs a file.
  KEY_FILE=""
  CLEANUP_KEY=0
  if [[ -f "$APPLE_API_KEY" ]]; then
    KEY_FILE="$APPLE_API_KEY"
  else
    KEY_FILE="$(mktemp -t langkeys-key).p8"
    CLEANUP_KEY=1
    umask 077
    printf '%s\n' "$APPLE_API_KEY" > "$KEY_FILE"
  fi
  cleanup() { [[ "$CLEANUP_KEY" == 1 ]] && rm -f "$KEY_FILE"; }
  trap cleanup EXIT

  echo "==> Signing with Developer ID (hardened runtime)"
  codesign --force --options runtime --timestamp \
    --identifier so.dou.langkeys --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  notarize() {
    xcrun notarytool submit "$1" \
      --key "$KEY_FILE" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait
  }

  # Two passes: the app is notarized and stapled first, so a copied-out app launches even
  # with no network. Stapling the DMG alone would not cover that.
  echo "==> Notarizing the app (uploads to Apple, takes a few minutes)"
  ditto -c -k --keepParent "$APP" build/LangKeys.zip
  notarize build/LangKeys.zip
  rm -f build/LangKeys.zip
  xcrun stapler staple "$APP"

  DMG="build/LangKeys-$VERSION.dmg"
  echo "==> Packaging $DMG"
  make_dmg "$DMG"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"

  echo "==> Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"

  echo "==> Done: $DMG (signed, notarized, stapled)"
  exit 0
fi

# Ad-hoc signature with a stable identifier so macOS keeps the Accessibility grant
# across rebuilds instead of asking again every time.
codesign --force --sign - --identifier so.dou.langkeys "$APP"

if [[ "$MODE" == "--dmg" ]]; then
  DMG="build/LangKeys-$VERSION.dmg"
  echo "==> Packaging $DMG"
  make_dmg "$DMG"
  echo "==> Done: $DMG"
  echo "    Ad-hoc signed — use ./build.sh --release to make one others can open."
elif [[ "$MODE" == "--install" ]]; then
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
