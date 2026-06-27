#!/bin/bash
set -euo pipefail

PRESET="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STABLE_SCRIPT_DIR="$HOME/.display-power/scripts"
PRESETS_FILE="$RESOURCES_DIR/references/presets.json"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.tern.display-power.caffeinate.plist"
LABEL="com.tern.display-power.caffeinate"
PREFS_DOMAIN="com.tern.display-power-toggle"
GUI_UID="$(id -u)"

usage() {
  echo "Usage: $0 <always-on|battery-default>"
  exit 1
}

ensure_stable_scripts() {
  mkdir -p "$STABLE_SCRIPT_DIR"
  cp -f "$SCRIPT_DIR/pmset-apply.sh" "$STABLE_SCRIPT_DIR/pmset-apply.sh" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/install-passwordless.sh" "$STABLE_SCRIPT_DIR/install-passwordless.sh" 2>/dev/null || true
  chmod +x "$STABLE_SCRIPT_DIR/"*.sh
}

[[ -n "$PRESET" ]] || usage
[[ -f "$PRESETS_FILE" ]] || { echo "Missing presets file: $PRESETS_FILE" >&2; exit 1; }

ensure_stable_scripts
PMSET_WRAPPER="$STABLE_SCRIPT_DIR/pmset-apply.sh"
INSTALL_PASSWORDLESS="$STABLE_SCRIPT_DIR/install-passwordless.sh"

apply_brightness() {
  local auto_brightness="$1"
  local dim_silent="$2"
  defaults write NSGlobalDomain AppleAutoBrightnessEnabled -bool "$auto_brightness"
  defaults -currentHost write .GlobalPreferences AppleAutoBrightnessEnabled -bool "$auto_brightness"
  defaults -currentHost write com.apple.BezelServices kDimBrightnessSilentOn -bool "$dim_silent"
  defaults write "$PREFS_DOMAIN" activePreset -string "$PRESET"
  killall cfprefsd 2>/dev/null || true
}

run_pmset() {
  if sudo -n "$PMSET_WRAPPER" "$PRESET" 2>/dev/null; then
    return 0
  fi
  if [[ -x "$INSTALL_PASSWORDLESS" ]]; then
    bash "$INSTALL_PASSWORDLESS" || true
    if sudo -n "$PMSET_WRAPPER" "$PRESET" 2>/dev/null; then
      return 0
    fi
  fi

  osascript <<EOF
do shell script "sudo " & quoted form of "$PMSET_WRAPPER" & " " & quoted form of "$PRESET" with administrator privileges
EOF
}

start_caffeinate() {
  mkdir -p "$(dirname "$LAUNCH_AGENT")"
  cat > "$LAUNCH_AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tern.display-power.caffeinate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-dims</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

  launchctl bootout "gui/${GUI_UID}/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/${GUI_UID}" "$LAUNCH_AGENT" 2>/dev/null || launchctl load -w "$LAUNCH_AGENT"
}

stop_caffeinate() {
  launchctl bootout "gui/${GUI_UID}/${LABEL}" 2>/dev/null || true
  launchctl unload -w "$LAUNCH_AGENT" 2>/dev/null || true
}

apply_always_on() {
  start_caffeinate
  run_pmset
  apply_brightness false true
}

apply_battery_default() {
  stop_caffeinate
  run_pmset
  apply_brightness true false
}

echo "Applying preset: $PRESET"

case "$PRESET" in
  always-on) apply_always_on ;;
  battery-default) apply_battery_default ;;
  *) echo "Unknown preset: $PRESET" >&2; usage ;;
esac

echo ""
echo "Current pmset settings:"
pmset -g custom | awk '/Battery Power|AC Power|displaysleep|sleep|lessbright/'

echo ""
echo "Done: $PRESET"