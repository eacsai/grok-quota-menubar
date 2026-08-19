# GrokQuota

macOS menu-bar extra that shows Grok Build weekly remaining percent and
the weekly reset time, using the local `grok login` in `~/.grok/auth.json`.

Title (cyan): `Grok 98% · 8/19 03:45`

This GitHub repository is a **private backup** of the first-party
source. Live install on the original machine still lives at
`~/.grok/quota-menubar/` until you clone elsewhere and run
`scripts/install.sh`.

## Repo map

| Path | Role |
|---|---|
| `Sources/GrokQuota/` | AppKit menu bar, billing client, sibling auth lock |
| `Tests/` | `swiftc` unit tests (no XCTest) |
| `Fixtures/` | Synthetic billing JSON (no tokens) |
| `scripts/build.sh` | Compile `dist/GrokQuota.app` |
| `scripts/test.sh` | Compile and run unit tests |
| `scripts/install.sh` | LaunchAgent `ai.xai.grok-quota-menubar` |
| `scripts/uninstall.sh` | Unload agent; does not touch `auth.json` |
| `docs/CODEX_RECOVERY.md` | Restore protocol |
| `docs/ASSET_MANIFEST.md` | Files that are not in git |

## Shortest restore

```bash
git clone git@github.com:eacsai/grok-quota-menubar.git
cd grok-quota-menubar
bash scripts/verify_backup.sh
bash scripts/restore_project.sh
```

Then, only if you want the menu bar on this Mac:

```bash
bash scripts/install.sh
```

`--once --json` (no tokens):

```bash
./dist/GrokQuota.app/Contents/MacOS/GrokQuota --once --json
```

## Tests

```bash
bash scripts/test.sh
```

## Residual risk

Refresh uses official Grok's sibling lock (`~/.grok/auth.json.lock`,
`pid:unix` holder + `flock`) for re-read, the refresh POST, and the
CAS write. If the disk refresh token already changed, the app adopts
it and does not POST. Official Grok running is not a hard ban.

A disk write failure after rotation is `写入失败`. If the lock cannot
be acquired in 25s and disk did not rotate, the error is `Grok占用中`.

Official Grok can still overwrite the file if it persists in-memory
tokens on a path that never re-reads disk.
