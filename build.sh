#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Display Power"
EXEC_NAME="DisplayPower"
VERSION="1.1.1"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
BINARY="$APP_DIR/Contents/MacOS/$EXEC_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swiftc "$ROOT/src/DisplayPowerToggle.swift" \
  -parse-as-library \
  -o "$BINARY" \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework UserNotifications

cp -R "$ROOT/scripts" "$APP_DIR/Contents/Resources/"
cp -R "$ROOT/references" "$APP_DIR/Contents/Resources/"
chmod +x "$APP_DIR/Contents/Resources/scripts/"*.sh

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hant</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.tern.display-power-toggle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Display Power</string>
</dict>
</plist>
PLIST

chmod +x "$BINARY"
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built: $APP_DIR"