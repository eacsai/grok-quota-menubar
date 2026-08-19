# Plan: speak official Grok sibling auth lock

confirmation_mode: approval_required
plan_approval_status: approved
plan_authority_evidence: current user message `按 sibling 锁协议改`

requested_outcome: GrokQuota refresh uses the same `auth.json.lock`
protocol official Grok 1.0.5 already implements for a sibling
process, so a later Grok persist can adopt T2 instead of writing T1.

## Evidence (local grok 1.0.5 strings)

- Lock path `auth.json.lock`; holder `pid:unix_seconds` (on-disk
  sample shape, 16 ASCII bytes).
- `unix-flock`; heartbeat rewrite; dead-pid stale recovery.
- `sibling-rotation detected` / `pick_up_sibling_token` /
  `another process already refreshed, using disk token`.
- Residual: a Grok persist path that never re-reads disk still
  cannot be closed from this app.

## Behavior

1. New `AuthLock.swift`. Exclusive acquire: open (create 0600 only
   if new), `LOCK_EX` with 25s poll, write holder, 2s heartbeat.
   Do not chmod an existing lock, do not unlink (avoids inode split).
   Flock is source of truth; dead holder is informational only.
2. Hold that lock for re-read + optional refresh POST + CAS persist.
   Release after persist (or failed POST).
3. Under lock, if disk `refresh_token` ≠ the snapshot we started
   with, adopt disk and do not POST.
4. Preemptive refresh if near expiry. 401 forces refresh even if
   expiry looks fine.
5. Official Grok running is **not** a hard ban. If the lock cannot
   be acquired in 25s, adopt disk if it rotated; else `Grok占用中`.
6. Billing GET stays outside the exclusive lock.
7. No install/restart of the live menu-bar app.

## Files

- `Sources/GrokQuota/AuthLock.swift` (new)
- `AuthStore.swift`, `BillingClient.swift`
- `scripts/build.sh`, `scripts/test.sh`
- `Tests/AuthLockTests.swift`, BillingClient tests, README

## Verification

`scripts/test.sh`; `scripts/build.sh`. No LaunchAgent kick.
