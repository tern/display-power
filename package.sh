#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"
APP_NAME="Display Power"
STAGING="$ROOT/dist/staging"
DMG_PATH="$ROOT/dist/DisplayPower-${VERSION}.dmg"

"$ROOT/build.sh"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$ROOT/dist/${APP_NAME}.app" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"
echo "Package: $DMG_PATH"
echo "Share this DMG with colleagues — drag the app to Applications."