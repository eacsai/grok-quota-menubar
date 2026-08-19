#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LABEL=ai.xai.grok-quota-menubar
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIN="$ROOT/dist/GrokQuota.app/Contents/MacOS/GrokQuota"
UID_NUM=$(id -u)
launchctl bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
rm -f "$PLIST"
if [ -n "$BIN" ]; then
  ps -ax -o pid=,command= | while read -r pid cmd; do
    if [ "$cmd" = "$BIN" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
fi
printf 'removed LaunchAgent %s\n' "$LABEL"
