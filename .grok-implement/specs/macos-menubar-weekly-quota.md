# Plan: macOS menu-bar weekly Grok quota (v3.1)

confirmation_mode: auto_completion_authorized
plan_approval_status: approved
plan_authority_evidence: >-
  current user message: 吸收这些 MED 做成 v3.1，不再审，直接实现
plan_revision: v3.1 absorbs v3 review HIGH-2 and MEDIUM-1..5 (in part).
  HIGH-1 discard-after-rotation is closed; Grok stale overwrite remains.
  Plan-phase and
  implementation-phase Codex reviews are waived for this cycle
  (`不再审`). v1/v2/v3 are not the implementable text.
requested_outcome: a local macOS menu-bar extra that always shows the current Grok Build weekly remaining percent and the weekly reset time, using the same account already stored by `grok login`.

## Why this is the full implementation path

This is a new multi-file app with credential use, a login-item deploy, and a
network client. The user authorized implementing this exact v3.1 text without
another Codex review. Residual `auth.json` TOCTOU after the Grok-running
probe is accepted.

## Evidence already gathered (read-only)

1. Official Grok TUI footer can show `Weekly limit left: N%`, but there is no
   documented config to keep it always visible, and the closed-source
   `~/.grok/bin/grok` binary must not be patched.
2. `grok` has `/usage` in the TUI and no CLI usage subcommand.
3. Local login lives in `~/.grok/auth.json` (OIDC, owner-only). The access
   token is the `key` field of the `https://auth.x.ai::<client-id>` entry.
   This plan never puts token values in source, tests, logs, review
   artifacts, or `--once` output.
4. Live probe (2026-08-18, token not printed) succeeded:

   ```text
   GET https://cli-chat-proxy.grok.com/v1/billing?format=credits
   Authorization: Bearer <auth.json key>
   ```

   Parsed keys (values redacted except non-secret shape):

   - `config.currentPeriod.type` = `USAGE_PERIOD_TYPE_WEEKLY`
   - `config.currentPeriod.start` / `end` = RFC3339 timestamps
   - `config.creditUsagePercent` = number (observed `2.0`) meaning **used**
   - `config.productUsage[]` has `{product: GrokBuild, usagePercent: 2.0}`
   - `config.billingPeriodStart` / `billingPeriodEnd` matched the weekly
     window in this probe
5. TUI wording is remaining (`limit left`). Used percent comes only from
   the unique `productUsage` row whose `product` is exactly `GrokBuild`.
   Do not fall back to aggregate `creditUsagePercent`.
6. Token refresh: issuer `https://auth.x.ai`,
   `token_endpoint` `https://auth.x.ai/oauth2/token`, `refresh_token`
   grant, public client (`none`). `oidc_client_id` is in `auth.json`.
   Observed `expires_at` is an RFC3339 UTC string with fractional seconds.
7. Toolchain: Swift 6.3.2 Command Line Tools, no full Xcode, no PyObjC,
   no rumps. `swiftc` + AppKit is the path.
8. On this host, review-proxy discovery now lives in
   `~/.local/bin/clash-port` (ClashX `*:port` first, skip Verge yaml and
   controller ports `9090/9091/9097/33331`, then `7897`/`7890` after `nc`).
   The menu-bar app inlines that same algorithm. It does not call the
   review driver at runtime.

## Non-goals

- Do not modify the official `grok` TUI, `~/.grok/bin/grok`, or TUI theme.
- Do not add `~/.grok/AGENTS.md`.
- Do not edit Codex skills or `run_codex_review.sh`.
- Do not invent quota when the API fails.
- Do not send tokens to any host other than `auth.x.ai` and
  `cli-chat-proxy.grok.com`.
- Do not git-commit, push, or publish the app.
- Do not *start* a refresh while official Grok is running. After a
  successful rotation, persist via CAS even if Grok appeared mid-POST.

## Deliverable layout

```text
~/.grok/quota-menubar/
  Sources/GrokQuota/
    main.swift
    AuthStore.swift
    BillingClient.swift
    ClashProxy.swift
    GrokProcess.swift          # official-Grok-running probe
    QuotaSnapshot.swift
  Tests/QuotaParserTests.swift
  Tests/AuthPolicyTests.swift  # fixtures only: CAS, grok-running, expires_in
  Fixtures/billing-weekly.json
  Fixtures/billing-non-weekly.json
  Fixtures/billing-missing-product.json
  Fixtures/billing-duplicate-product.json
  Fixtures/billing-used-bounds.json
  Fixtures/billing-expired-period.json
  Resources/Info.plist
  scripts/build.sh
  scripts/install.sh
  scripts/uninstall.sh
  README.md
```

Built app: `~/.grok/quota-menubar/dist/GrokQuota.app`  
LaunchAgent: `~/Library/LaunchAgents/ai.xai.grok-quota-menubar.plist`

`--once --json` is a CLI mode of the same binary: print one JSON object to
stdout (`ok`, `remaining_percent`, `used_percent`, `period_type`,
`reset_at_local`, or `ok=false` + `error_class`). No tokens, no proxy
port, no Authorization header.

## Runtime behavior

Menu-bar title (always visible, cyan attributed text):

```text
Grok 98% · 8/19 03:45
```

- `98%` is weekly **remaining** for Grok Build after a valid, **active**
  parse.
- Time is `currentPeriod.end` in the local timezone, compact `M/d HH:mm`.

Each successful snapshot stores `fetchedAt` (monotonic + wall clock).

State table (title + menu):

| State | Title | Menu |
|---|---|---|
| no snapshot + failure | `Grok ?` | error class only |
| refreshing, no snapshot | `Grok …` | `正在更新` |
| fresh active snapshot | `Grok 98% · 8/19 03:45` | used / remaining / weekly / full reset / `更新于` |
| stale but still-active snapshot + failure, age ≤ 6h | keep last title | last numbers + `数据可能过期` + error class |
| snapshot period ended (`now >= end + 120s`) | `Grok ?` | `周期已结束` + last reset time; **no percent in the title** |
| stale age > 6h (even if period still active) | `Grok ?` | last numbers + `数据可能过期` + error class; **no percent in the title** |
| parse/auth failure after a still-active snapshot, age ≤ 6h | keep last title | last numbers + new error class |

Error classes: `未登录` / `登录已过期` / `网络失败` / `解析失败` /
`Grok占用中` / `写入失败` / `周期未开始` / `周期已结束`.
Never the token.

Menu items: used / remaining / weekly (valid parse only); full local reset;
Refresh now; Open `https://grok.com/?_s=usage`; Quit (exit 0;
`KeepAlive.SuccessfulExit=false`).

Triggers: 300s timer, Mac wake, status-item click. Single-flight: coalesce
into one in-flight recovery sequence (defined below). Monotonic 30s
minimum between **user/timer-triggered** billing sequences. The one
post-401 billing retry is part of the same sequence and is not separately
throttled.

## Quota parse rules

A snapshot is valid only when all of the following hold:

- `config.currentPeriod.type` is exactly `USAGE_PERIOD_TYPE_WEEKLY`
- `config.currentPeriod.start` and `end` both parse as RFC3339
- `start - 120s <= now < end + 120s` (120s clock-skew allowance)
- `config.productUsage` contains **exactly one** row with `product == "GrokBuild"`
- that row's `usagePercent` is a finite number in `[0, 100]`

Additionally require `start < end`. Classification:

- `start >= end` or unparsable type/timestamps/product/usage → `解析失败`
- `now < start - 120s` → `周期未开始` (not an active snapshot; no title %)
- `now >= end + 120s` → `周期已结束` (no title %)
- otherwise, if the GrokBuild row is valid → active snapshot

Do not display aggregate `creditUsagePercent`. Do not display a non-weekly
period as weekly.

Remaining percent = `100 - lround(usagePercent)`, then clamp to `[0, 100]`.
`lround` is half-away-from-zero. Therefore used `2.5` → remaining **97**.
TUI fractional rounding is not evidenced.

## Official Grok running probe

`officialGrokRunning` is true if any process has an executable realpath
that is `~/.grok/bin/grok` or a regular file under `~/.grok/downloads/`
whose basename matches `grok-*`. Do not match this menu-bar app, do not
match `clash-port`, and do not match unrelated binaries named `grok`.

Open `~/.grok/auth.json.lock` with `O_RDWR|O_CREAT` and mode `0600`
(create if missing; do not replace an existing inode). If an exclusive
`flock` cannot be acquired immediately, treat that as another writer for
write/refresh decisions (same effect as Grok running: no POST, no write).

## Credential handling

1. Read only `~/.grok/auth.json`. Select the unique object key matching
   `https://auth.x.ai::<uuid>` whose `oidc_issuer` is `https://auth.x.ai`
   and whose `oidc_client_id` matches the key suffix. If zero or more than
   one such entry exists, fail as `未登录` and do not write.
2. Honor `~/.grok/auth.json.lock` as specified above. Shared lock for
   short reads; exclusive lock for the compare-and-swap write, **held
   through reread + rename** (not across the network). Stored `key` and
   `refresh_token` must be nonempty strings or the entry is `未登录`.
3. Snapshot `oidc_client_id`, `key`, and `refresh_token` under a short
   shared lock, then drop the lock. Use `key` as the Bearer token.
4. Refresh is allowed only when **all** of these hold:
   - `officialGrokRunning` is false
   - exclusive lock is acquirable (no other writer)
   - this sequence has not already POSTed refresh
   - `expires_at` is within 5 minutes, missing, unparsable, **or** the
     in-sequence billing GET returned 401
   If Grok is running or the lock is busy, stay read-only: never POST
   refresh, never write `auth.json`. A 401 in that state is `Grok占用中`.
5. Allowed refresh request:

   ```text
   POST https://auth.x.ai/oauth2/token
   Content-Type: application/x-www-form-urlencoded
   grant_type=refresh_token
   refresh_token=<percent-encoded snapshot>
   client_id=<percent-encoded oidc_client_id>
   ```

   Public client: no client secret. HTTPS only. **Reject every HTTP
   redirect.** Application/x-www-form-urlencoded percent-encoding is
   required. Accept only HTTP 2xx with JSON `access_token` a non-empty
   string and `expires_in` a finite number in `[60, 172800]`. If
   `refresh_token` is present it must be a non-empty string; if absent,
   keep the existing refresh token.
6. On refresh success, **always** try to persist the new tokens. Do not
   discard a rotated refresh token just because official Grok started
   during the POST (that is what used to lose the login). Reacquire an
   exclusive lock (retry ~1s), reread, and write only if that same
   entry's `oidc_client_id`, `key`, and `refresh_token` still equal the
   snapshot used for the POST. If CAS no longer matches, keep the newer
   on-disk entry. If the lock cannot be taken, still attempt the same
   CAS write (last resort after rotation).
7. Allowed write, and only when CAS matches: replace `key` with
   `access_token`; replace `refresh_token` only if the response includes a
   non-empty new one; set `expires_at` to now+`expires_in` as an RFC3339
   UTC string with fractional seconds. Preserve every other key and every
   other top-level auth entry. File mode stays `0600`.
8. Atomic write (the only permitted credential copy): create a same-
   directory temp with `O_CREAT|O_EXCL` and mode `0600` from the first
   byte; write the full JSON; `fsync` the file; atomic rename over
   `auth.json`; `fsync` the parent directory; unlink the temp on every
   failure path. No backup file. This transient copy is allowed; any
   other copy is not. A later overwrite by official Grok with a stale
   in-memory copy cannot be prevented without a shared broker.
9. Never print, log, or copy tokens except that transient write.

## Billing recovery sequence (one in-flight unit)

Budget for one sequence: **at most one refresh POST** and **at most two
logical billing GETs**. A proxy retry is a transport retry of the same
GET, not a third GET. **Never** proxy-retry or otherwise resend a
refresh POST. An indeterminate refresh outcome is a hard failure.

Error map:

| Condition | `error_class` |
|---|---|
| no/ambiguous auth entry, empty `key`/`refresh_token` | `未登录` |
| official Grok running or lock busy, and token unusable (401 or expired with refresh forbidden) | `Grok占用中` |
| refresh allowed but 401 after the one refresh, or expired with no refresh token, or refresh 400/403 / OAuth `invalid_grant` | `登录已过期` |
| refresh 2xx but CAS persist I/O failed after retries | `写入失败` |
| connection/TLS/redirect-rejected/non-2xx other than 401/400/403-on-refresh | `网络失败` |
| JSON does not satisfy parse rules | `解析失败` |
| `now < start - 120s` | `周期未开始` |
| `now >= end + 120s` | `周期已结束` |

Steps:

1. If a sequence is already in flight, coalesce.
2. If this is a new user/timer trigger and the last sequence started
   < 30s ago on the monotonic clock, skip.
3. Snapshot credentials. If Grok is not running and `expires_at` is
   within 5 minutes / missing / unparsable, do the one allowed refresh
   **before** GET (this consumes the refresh budget).
4. Logical GET #1 with the current access token. On connection failure
   only: one proxy-fallback retry of this GET.
5. If GET returns 401 and refresh budget remains and Grok is not
   running: do the one refresh, then logical GET #2 (one connection
   proxy retry allowed on GET #2). If 401 and refresh is not allowed:
   `Grok占用中`. If 401 and refresh was already used: `登录已过期`.
6. Other non-2xx, rejected billing redirect, or empty body: `网络失败`.
   Do not parse error bodies as billing JSON.
7. Parse 2xx with the quota rules. Success replaces the snapshot and
   `fetchedAt`.

## Network

- Ephemeral `URLSession`: cookies, URL cache, and credential storage
  disabled. Never weaken TLS.
- Allowed origins are constant HTTPS hosts only:
  `https://auth.x.ai` and `https://cli-chat-proxy.grok.com`.
- Token refresh: reject all redirects.
- Billing GET: follow at most one hop and only when the next URL is
  `https` with host exactly `cli-chat-proxy.grok.com` and default port.
- Default reachability: system proxy (Clash system/TUN).
- Fallback after a **connection** error only, inlined (single authority,
  do not call `run_codex_review.sh`):

  1. `lsof` TCP LISTEN. Skip ports `9090`, `9091`, `9097`, `33331`.
  2. Prefer a `ClashX` listener on `*:port`, then ClashX `127.0.0.1:7897`,
     then ClashX `127.0.0.1:7890`, then other ClashX loopback.
  3. Skip process names matching Verge.
  4. Then `mihomo`/`clash` on `*:port`, then those on `7897`/`7890`.
  5. `nc -z -G 1 127.0.0.1 <port>`. If none, try `7897` then `7890` only
     after `nc` succeeds.
  6. Retry **only the failed billing GET** once via
     `http://127.0.0.1:<port>` as a proxy. Destination URL stays the
     original allowed origin. Do not apply this fallback to token
     refresh.
  7. Do not log the chosen port.

- Timeouts: 20 seconds connect+read.
- User-Agent: `GrokQuota/1.0`.
- Extra headers: `x-grok-client-identifier: grok-shell`,
  `x-grok-client-version: 1.0.5`, `X-XAI-Token-Auth: xai-grok-cli`.

## Install / uninstall

`scripts/install.sh`:

1. Compile the `.app` with `swiftc` + AppKit/Foundation.
2. Write the LaunchAgent plist: `RunAtLoad=true`,
   `KeepAlive.SuccessfulExit=false`. Logs under
   `~/.grok/quota-menubar/logs/` (no secrets).
3. `launchctl bootout` then `bootstrap` the user domain.

`scripts/uninstall.sh` bootouts the agent, removes the plist, and leaves
source in place. It does not touch `auth.json`.

## Verification (after approval, before claiming done)

1. `bash -n` on install/uninstall scripts.
2. Parser tests:
   - weekly GrokBuild used `2.0` → remaining `98`
   - used `0`, `100`, `2.5` → remaining `100`, `0`, **97**
   - used `-1`, `101`, non-finite → `解析失败`
   - non-weekly, missing GrokBuild, duplicate GrokBuild → `解析失败`
   - period `end` in the past beyond skew → `周期已结束`
   - `start >= end`, future period → `解析失败` / `周期未开始`
3. Policy tests via `scripts/test.sh` (`swiftc` test binary, no XCTest)
   with **synthetic** auth files only: CAS mismatch ⇒ no write; successful
   rotation snapshot ⇒ write even conceptually after Grok appears; bad
   `expires_in` ⇒ no write; empty stored tokens ⇒ `未登录`; form
   encoding of reserved characters; 0600 exclusive temp.
4. `scripts/build.sh` produces a runnable `.app`.
5. Live `--once --json` on this machine: remaining percent, period type,
   local reset time only. Confirm weekly + GrokBuild. No tokens.
6. After install, confirm a status item in the menu bar (visual or
   Accessibility description of `NSStatusItem`), not merely `pgrep`.
   Quit must leave the process dead (SuccessfulExit=false).

## Frozen consequential actions (authorized by the current message)

- class: credential_use  
  exact_target: read `~/.grok/auth.json`; refresh via
  `https://auth.x.ai/oauth2/token` **only when official Grok is not
  running**; CAS-update the same file  
  authority_evidence: 吸收这些 MED 做成 v3.1，不再审，直接实现
- class: deploy  
  exact_target: build `~/.grok/quota-menubar/dist/GrokQuota.app` and load
  `~/Library/LaunchAgents/ai.xai.grok-quota-menubar.plist`  
  authority_evidence: same current message plus the original menu-bar request

No git commit, push, deletion of `auth.json`, or external message.

## Rollback

Run `scripts/uninstall.sh`. Source remains under `~/.grok/quota-menubar`.

## Open implementation notes (not blockers)

- If billing JSON changes, fail closed with `解析失败`.
- Do not add a Dock icon (`LSUIElement`).
- Do not assume the official CLI honors `auth.json.lock`.
- Do not edit `run_codex_review.sh` as part of this app.
