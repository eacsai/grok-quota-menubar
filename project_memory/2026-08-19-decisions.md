# Decisions (2026-08-19)

- Menu-bar title is cyan (`NSColor.systemCyan`); remaining percent is
  `100 - lround(GrokBuild usagePercent)` from the unique product row.
- Refresh uses official sibling lock: `auth.json.lock` holder
  `pid:unix` plus `flock`; hold across re-read, refresh POST, CAS write.
- Do not start a refresh POST if disk already shows a different
  refresh token (adopt sibling).
- Official Grok running is not a hard ban once the sibling lock is held.
- Heartbeat must not `dispatch_sync` onto its own serial queue.
- Lock-held refresh POST timeout is 10s; billing GET stays 20s.
- Tests must not spawn Apple CLT `/usr/bin/python3` (Python.app can
  SIGTRAP). Lock-holder child is `/usr/bin/perl`.
- LaunchAgent label: `ai.xai.grok-quota-menubar`.
  `KeepAlive.SuccessfulExit=false`.
- Tokens never appear in `--once --json`, logs, or this repository.
