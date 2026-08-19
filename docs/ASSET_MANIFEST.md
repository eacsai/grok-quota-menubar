# Asset manifest (not uploaded)

| Name | Why omitted | Recover |
|---|---|---|
| `~/.grok/auth.json` | OIDC tokens | User runs official `grok login`. Never copy this file into git. |
| `~/.grok/auth.json.lock` | Live sibling lock | Recreated at runtime by GrokQuota / official Grok. |
| `dist/GrokQuota.app` | Built binary | `bash scripts/build.sh` |
| `.build/quota-tests` | Test binary | `bash scripts/test.sh` |
| `logs/stdout.log`, `logs/stderr.log` | LaunchAgent logs | Recreated by `install.sh` |
| `.grok-implement/reviews/` | Local Cursor/Codex review receipts | Not required to build. Plans are in `.grok-implement/specs/`. |
| Official `~/.grok/bin/grok` | Closed-source CLI | Install official Grok Build TUI; do not vendor. |
| ClashX mixed-port listener | Local proxy | Optional; app falls back to 7897/7890 after `nc`. |

No datasets, weights, or papers belong to this project.

Provenance path on the source machine (not a restore command):
`/Users/wangqw/.grok/quota-menubar`.
