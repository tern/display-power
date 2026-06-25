#!/bin/bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="$SKILL_DIR/references/current-state.json"

read_pmset_value() {
  local profile="$1"
  local key="$2"
  pmset -g custom | awk -v profile="$profile" -v key="$key" '
    $0 == profile ":" { in_profile=1; next }
    in_profile && $1 == key { print $2; exit }
    in_profile && $0 ~ /^[^ ]/ { in_profile=0 }
  '
}

battery_displaysleep=$(read_pmset_value "Battery Power" "displaysleep")
battery_sleep=$(read_pmset_value "Battery Power" "sleep")
battery_lessbright=$(read_pmset_value "Battery Power" "lessbright")
ac_displaysleep=$(read_pmset_value "AC Power" "displaysleep")
ac_sleep=$(read_pmset_value "AC Power" "sleep")

auto_brightness=$(defaults read NSGlobalDomain AppleAutoBrightnessEnabled 2>/dev/null || echo "unset")
dim_silent=$(defaults -currentHost read com.apple.BezelServices kDimBrightnessSilentOn 2>/dev/null || echo "unset")

cat > "$OUT_FILE" <<EOF
{
  "savedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pmset": {
    "battery": {
      "displaysleep": ${battery_displaysleep:-null},
      "sleep": ${battery_sleep:-null},
      "lessbright": ${battery_lessbright:-null}
    },
    "ac": {
      "displaysleep": ${ac_displaysleep:-null},
      "sleep": ${ac_sleep:-null}
    }
  },
  "brightness": {
    "AppleAutoBrightnessEnabled": ${auto_brightness:-null},
    "kDimBrightnessSilentOn": ${dim_silent:-null}
  }
}
EOF

echo "Saved current state to: $OUT_FILE"
cat "$OUT_FILE"