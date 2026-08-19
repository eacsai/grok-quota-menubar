#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="${1:-$ROOT/dist/GrokQuota.app}"
STAGE="${APP}.tmpbuild"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"
swiftc -O \
  -o "$STAGE/Contents/MacOS/GrokQuota" \
  -framework AppKit \
  -framework Foundation \
  "$ROOT/Sources/GrokQuota/QuotaSnapshot.swift" \
  "$ROOT/Sources/GrokQuota/AuthStore.swift" \
  "$ROOT/Sources/GrokQuota/AuthLock.swift" \
  "$ROOT/Sources/GrokQuota/GrokProcess.swift" \
  "$ROOT/Sources/GrokQuota/ClashProxy.swift" \
  "$ROOT/Sources/GrokQuota/HTTPClient.swift" \
  "$ROOT/Sources/GrokQuota/BillingClient.swift" \
  "$ROOT/Sources/GrokQuota/main.swift"
chmod 755 "$STAGE/Contents/MacOS/GrokQuota"
rm -rf "$APP"
mv "$STAGE" "$APP"
printf '%s\n' "$APP"
