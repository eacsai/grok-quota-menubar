#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/.build"
swiftc -O \
  -o "$ROOT/.build/quota-tests" \
  -framework Foundation \
  "$ROOT/Sources/GrokQuota/QuotaSnapshot.swift" \
  "$ROOT/Sources/GrokQuota/AuthStore.swift" \
  "$ROOT/Sources/GrokQuota/AuthLock.swift" \
  "$ROOT/Sources/GrokQuota/GrokProcess.swift" \
  "$ROOT/Sources/GrokQuota/ClashProxy.swift" \
  "$ROOT/Sources/GrokQuota/HTTPClient.swift" \
  "$ROOT/Sources/GrokQuota/BillingClient.swift" \
  "$ROOT/Tests/QuotaParserTests.swift" \
  "$ROOT/Tests/AuthPolicyTests.swift" \
  "$ROOT/Tests/ClashProxyTests.swift" \
  "$ROOT/Tests/GrokProcessTests.swift" \
  "$ROOT/Tests/BillingClientTests.swift" \
  "$ROOT/Tests/AuthLockTests.swift" \
  "$ROOT/Tests/TestMain.swift"
(cd "$ROOT" && "$ROOT/.build/quota-tests")
