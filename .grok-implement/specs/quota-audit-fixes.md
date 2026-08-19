# Plan: absorb GrokQuota audit AWC (HIGH+MEDIUM+LOW)

confirmation_mode: approval_required
plan_approval_status: approved
plan_authority_evidence: >-
  current user message: 能收的全收（含 LOW）
requested_outcome: implement every accepted finding from
  `20260819T092616Z-quota-audit-cursor` in the GrokQuota sources,
  tests, and install scripts. Do not reinstall or restart the live
  menu-bar app. Implementation-phase Cursor review after writes.

## Scope

Audit: `.grok-implement/reviews/20260819T092616Z-quota-audit-cursor/`
L-2 is comment/clarity only (not a behavior defect).
Known residual risk (official Grok stale overwrite) stays.

## Changes

1. HIGH-1: `PersistResult` wrote|casMismatch|writeFailed; retry
   writeFailed; still fail → `QuotaError.persistFailed` (`写入失败`).
   Never treat write I/O fail as CAS miss.
2. M1: refresh non-2xx 400/403 or OAuth `invalid_grant` /
   `invalid_client` / `unauthorized_client` → `登录已过期`.
3. M2: coalesce kicks on the serial queue (`pending` + `drain`);
   30s throttle for timer/menu/立即刷新; wake exempt.
4. M3: store `fetchedMonoNanos`; stale age = max(wall, mono).
5. M4: rank known mixed ports 7897/7890 above ClashX `*:` other ports.
6. M5: compile BillingClient+HTTPClient in `test.sh`; add fixture
   tests for refresh error map and persist tri-state.
7. L-1: 401 uses grok-running at token-use time; delete dead ternary.
8. L-2: make lock-retry vs CAS-without-lock obvious; same behavior.
9. L-3: ASCII unreserved form-encode; encode failure does not send
   empty token.
10. L-4: reject `Bool` before `NSNumber` in percent and expires_in.
11. L-5: assert `expiresAt` in select-entry test.
12. L-6: last `host:port` field; use lsof stdout even if exit ≠ 0.
13. L-7: oversize `proc_listpids` buffer; retry if filled.
14. L-8: bootout first; compile to staging; replace on success;
    kill only exact `GrokQuota` binary path.

## Frozen actions

- Edit sources, tests, scripts, README error list.
- Run `scripts/test.sh` and `scripts/build.sh`.
- No install/uninstall, no LaunchAgent kick, no commit/push.

## Verification

`scripts/test.sh` green; `bash -n` scripts; `scripts/build.sh`
produces the app; no live agent restart.
