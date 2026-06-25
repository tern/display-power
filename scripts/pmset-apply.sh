#!/bin/bash
# Fixed pmset commands only — used with passwordless sudo.
set -euo pipefail

PRESET="${1:-}"

case "$PRESET" in
  always-on)
    pmset -a displaysleep 0 sleep 0 lessbright 0
    /usr/libexec/PlistBuddy -c "Set :'Battery Power':'Display Sleep Timer' 0" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'AC Power':'Display Sleep Timer' 0" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'Battery Power':'System Sleep Timer' 0" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'AC Power':'System Sleep Timer' 0" /Library/Preferences/com.apple.PowerManagement.plist
    ;;
  battery-default)
    pmset -b displaysleep 2 sleep 1 lessbright 0
    pmset -c displaysleep 10 sleep 1
    /usr/libexec/PlistBuddy -c "Set :'Battery Power':'Display Sleep Timer' 2" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'AC Power':'Display Sleep Timer' 10" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'Battery Power':'System Sleep Timer' 1" /Library/Preferences/com.apple.PowerManagement.plist
    /usr/libexec/PlistBuddy -c "Set :'AC Power':'System Sleep Timer' 1" /Library/Preferences/com.apple.PowerManagement.plist
    ;;
  *)
    echo "Unknown preset: $PRESET" >&2
    exit 1
    ;;
esac