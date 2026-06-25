#!/bin/bash
set -euo pipefail

WRAPPER="$(cd "$(dirname "$0")" && pwd)/pmset-apply.sh"
USER_NAME="$(whoami)"
SUDOERS_FILE="/etc/sudoers.d/display-power-${USER_NAME}"
LINE="${USER_NAME} ALL=(ALL) NOPASSWD: ${WRAPPER}"

if [[ ! -x "$WRAPPER" ]]; then
  chmod +x "$WRAPPER"
fi

if sudo -n "$WRAPPER" always-on 2>/dev/null; then
  sudo "$WRAPPER" battery-default
  echo "Passwordless pmset already configured."
  exit 0
fi

TMP="$(mktemp)"
printf '%s\n' "$LINE" > "$TMP"
chmod 0440 "$TMP"

osascript <<APPLESCRIPT
do shell script "cp ${TMP} ${SUDOERS_FILE} && chown root:wheel ${SUDOERS_FILE} && chmod 0440 ${SUDOERS_FILE} && visudo -cf ${SUDOERS_FILE}" with administrator privileges
APPLESCRIPT

rm -f "$TMP"
echo "Passwordless pmset enabled for ${WRAPPER}"