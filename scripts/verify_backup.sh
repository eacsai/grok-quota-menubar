#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail=0

need() {
  if [ ! -e "$1" ]; then
    printf 'MISSING %s\n' "$1" >&2
    fail=1
  fi
}

need AGENTS.md
need README.md
need docs/CODEX_RECOVERY.md
need docs/ASSET_MANIFEST.md
need docs/EXPERIMENT_RESULTS.md
need docs/RESEARCH_ROADMAP.md
need project_memory/2026-08-19-decisions.md
need Sources/GrokQuota/main.swift
need Sources/GrokQuota/AuthLock.swift
need scripts/test.sh
need scripts/build.sh
need scripts/restore_project.sh

if [ -e auth.json ] || [ -e .env ]; then
  printf 'BLOCKER credential-like file in tree\n' >&2
  fail=1
fi

# Paths only; do not print file contents.
while IFS= read -r -d '' f; do
  printf 'BLOCKER secret-like name %s\n' "$f" >&2
  fail=1
done < <(find . -type f \( -name 'auth.json' -o -name '*.pem' -o -name '*.p12' -o -name '.env' \) -print0 2>/dev/null)

if find . -type f -size +10M | grep -q .; then
  printf 'BLOCKER file larger than 10MiB\n' >&2
  find . -type f -size +10M -print >&2
  fail=1
fi

if [ -d dist/GrokQuota.app ] || [ -x .build/quota-tests ]; then
  printf 'WARN built artifacts present (should be gitignored)\n' >&2
fi

if [ "$fail" -ne 0 ]; then
  printf 'verify_backup: FAIL\n' >&2
  exit 1
fi
printf 'verify_backup: OK\n'
