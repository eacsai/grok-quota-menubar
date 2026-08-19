#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LABEL=ai.xai.grok-quota-menubar
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP="$ROOT/dist/GrokQuota.app"
BIN="$APP/Contents/MacOS/GrokQuota"
STAGE="$ROOT/dist/GrokQuota.app.new"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR" "$HOME/Library/LaunchAgents" "$ROOT/dist"

stop_exact() {
  target=$1
  [ -n "$target" ] || return 0
  ps -ax -o pid=,command= | while read -r pid cmd; do
    if [ "$cmd" = "$target" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
}

UID_NUM=$(id -u)
launchctl bootout "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
stop_exact "$BIN"

rm -rf "$STAGE"
if ! bash "$ROOT/scripts/build.sh" "$STAGE"; then
  printf 'build failed; previous app left in place\n' >&2
  exit 1
fi
rm -rf "$APP"
mv "$STAGE" "$APP"

umask 077
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOGDIR}/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOGDIR}/stderr.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
launchctl enable "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || true
printf 'installed %s\n' "$PLIST"
