#!/bin/bash
set -euo pipefail

APP_PATH="${1:-/Applications/Display Power.app}"
LABEL="com.tern.display-power.launcher"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
GUI_UID="$(id -u)"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Install Display Power.app to Applications first." >&2
  exit 1
fi

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

launchctl bootout "gui/${GUI_UID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${GUI_UID}" "$PLIST"

echo "Login item enabled: $APP_PATH"
echo "Display Power will start automatically on login."