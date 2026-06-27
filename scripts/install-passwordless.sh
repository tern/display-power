#!/bin/bash
set -euo pipefail

STABLE_DIR="$HOME/.display-power/scripts"
WRAPPER="$STABLE_DIR/pmset-apply.sh"
USER_NAME="$(whoami)"
SUDOERS_FILE="/etc/sudoers.d/display-power-${USER_NAME}"
LINE="${USER_NAME} ALL=(ALL) NOPASSWD: ${WRAPPER}"

if [[ ! -x "$WRAPPER" ]]; then
  echo "Missing wrapper: $WRAPPER" >&2
  exit 1
fi

if sudo -n "$WRAPPER" always-on 2>/dev/null; then
  echo "Passwordless pmset already configured."
  exit 0
fi

TMP="$(mktemp)"
printf '%s\n' "$LINE" > "$TMP"
chmod 0440 "$TMP"

osascript <<EOF
do shell script "cp " & quoted form of "$TMP" & " " & quoted form of "$SUDOERS_FILE" & " && chown root:wheel " & quoted form of "$SUDOERS_FILE" & " && chmod 0440 " & quoted form of "$SUDOERS_FILE" & " && visudo -cf " & quoted form of "$SUDOERS_FILE" with administrator privileges
EOF

rm -f "$TMP"
echo "Passwordless pmset enabled for ${WRAPPER}"