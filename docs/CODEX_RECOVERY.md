# Codex recovery

## Identity

| Field | Value |
|---|---|
| Project | GrokQuota macOS menu-bar weekly quota |
| GitHub | `eacsai/grok-quota-menubar` (private) |
| Authoritative source in this backup | first-party Swift + scripts in this repo |
| Live machine path (provenance only) | `~/.grok/quota-menubar` |

## Stages

1. **Clone** this repository. Confirm `HEAD` and that `AGENTS.md` exists.
2. **Verify payload** with `bash scripts/verify_backup.sh`.
3. **Restore compile/test** with `bash scripts/restore_project.sh`.
   Requires macOS `swiftc` (Command Line Tools). Does **not** install
   the LaunchAgent.
4. **Login** is local: official `grok login` writes `~/.grok/auth.json`.
   That file is never in git. If it is missing, the user must log in.
5. **Install** (optional, needs explicit user yes):
   `bash scripts/install.sh`.

## Status table

| Gate | How to pass |
|---|---|
| Clone | `git rev-parse HEAD` matches the recorded SHA |
| No secrets | `verify_backup.sh` finds no `auth.json` / `.env` / keys |
| Unit tests | `scripts/test.sh` prints `all tests passed` |
| App binary | `scripts/build.sh` writes `dist/GrokQuota.app` |
| Live quota | `--once --json` returns `ok:true` only after `grok login` |

## Done when

A fresh clone on a new Mac can compile, pass `scripts/test.sh`, and
build the app. Menu-bar install and a live billing read still need the
user's `grok login` and an explicit install request.
