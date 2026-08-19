#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() { printf 'restore: %s\n' "$*" >&2; exit 1; }

[ -f AGENTS.md ] && [ -f scripts/test.sh ] || fail "not a GrokQuota backup checkout"
command -v swiftc >/dev/null || fail "swiftc missing; install macOS Command Line Tools"
command -v git >/dev/null || fail "git missing"

printf 'repo %s\n' "$(git rev-parse --show-toplevel)"
printf 'HEAD %s\n' "$(git rev-parse HEAD)"

if [ -d .git/lfs ]; then
  git lfs pull || true
fi

bash "$ROOT/scripts/verify_backup.sh"
bash "$ROOT/scripts/test.sh"
bash "$ROOT/scripts/build.sh"

printf 'restore: compile/test/build OK\n'
printf 'restore: not installing LaunchAgent (needs explicit user yes)\n'
printf 'restore: live quota needs local grok login (~/.grok/auth.json)\n'
