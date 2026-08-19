# AGENTS

This repository is the portable backup of **GrokQuota**, a local macOS
menu-bar extra that shows Grok Build weekly remaining percent and reset
time using the machine's existing `grok login`.

## First reads

1. `README.md` — what it is and how to build/test/install
2. `docs/CODEX_RECOVERY.md` — restore stages and gates
3. `docs/ASSET_MANIFEST.md` — what is not in git and how to recover it

## Standing authorization

If the user asks to restore, resume, take over, or only sends this
repository URL, do the **read-only and reversible** restore path without
asking them to repeat these instructions:

- clone/fetch this repo
- run `scripts/verify_backup.sh`
- run `scripts/restore_project.sh` (compiles and runs unit tests)
- read the docs above and continue the local app work

Still stop and report, do not fake “fully automatic”:

- GitHub / `gh` login
- writing or rotating `~/.grok/auth.json`
- installing or restarting the live LaunchAgent / menu-bar process
  unless the current message explicitly says to install or run it
- sudo, overwriting a different existing GrokQuota install the user
  did not name

## Boundaries

- Do not upload tokens, cookies, `auth.json`, or lock-file contents.
- Do not patch official `~/.grok/bin/grok`.
- Do not force-push or rewrite published history.
- First-party code lives under `Sources/`, `Tests/`, `scripts/`,
  `Fixtures/`, `Resources/`.
