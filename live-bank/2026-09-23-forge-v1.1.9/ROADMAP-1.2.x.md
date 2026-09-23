# Forge 1.2.x roadmap from the 1.1.9 bank

This roadmap starts from the accepted 1.1.9 live state documented in this folder.

## 1.2.0 - transient room-context correctness

Goal: make current-room context genuinely transient for both Luna and Sol while preserving normal native conversation history and warm-session behaviour.

### Luna

Required behaviour:
- latest-10 room snapshot is visible to the current Luna inference
- latest-10 is non-durable
- genuine current user message remains durable when a real reply occurs
- genuine Luna assistant reply remains durable
- exact `NO_REPLY` leaves no user/assistant native turn behind
- ordinary input growth should fall from the current ~700-1,100/turn toward real-turn-sized growth, ideally tens to low hundreds for short turns
- preserve Luna sidecar reuse
- preserve warm thread/cache behaviour
- no generic rollback of unrelated monitor/tool turns

Known investigation result:
- simply removing `!forgeTransientToolTxnMonitorV1` is insufficient
- tested Luna monitor finalizer state had `monitor:true` but no transaction `toolThreadId/toolTurnId`
- therefore transaction arming/lifecycle must be fixed explicitly
- v1m's post-turn lexical-scope failure must not be repeated

Desired semantic transaction:
1. current-turn latest-10 reaches model
2. dirty transient carrier is removed from durable native history
3. if the answer is real, retain/reinject only clean actual user + assistant
4. if the answer is exact `NO_REPLY`, retain/reinject nothing
5. one transaction owns the operation; no competing FINAL9 semantic rollback

### Sol

Required behaviour:
- latest-10 actually reaches the native model/provider input
- latest-10 remains non-durable
- warm Sol stays on the same native thread
- existing native conversation history stays compact
- preserve the excellent warm-cache pattern seen at the 1.1.9 bank
- validate receipt at the actual turn/start/provider boundary, not merely an early hook
- use a Discord behavioural recall canary as part of acceptance

### 1.2.0 acceptance

- Luna normal reply persists as clean user + assistant
- Luna exact `NO_REPLY` creates no effective native history entry
- Luna no longer grows ~1k per short turn
- Sol behavioural test proves latest-10 receipt
- transient room snapshot does not persist on either model
- Luna sidecar does not churn
- Sol warm native thread does not churn
- cache remains healthy
- no duplicate rollback/reinject
- no harness/post-turn scope exceptions
- rollback to this 1.1.9 bank remains available

## 1.2.1 - rolling sessions

Goal: make genuine Sol rollover deliberate, config-driven and continuity-safe.

Required design:
- one rollover authority:
  resolved config -> `solRolloverTokens` -> Codex rollover decision
- remove duplicate/hardcoded threshold ownership
- fresh Sol thread receives a bounded canonical recent Sol tail of approximately 20k tokens
- retain persistent/transitory memory
- retain current-room context
- retain cross-model continuity
- do not replay the full old transcript
- do not repeatedly churn sessions
- Luna must not use the Sol fresh-history bootstrap path

Reference-only older V5 branch may contain useful mechanisms such as:
- `FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1`
- `FORGE_CODEX_ROLLOVER_CONFIG_V5`
- principal native thread ID publication if still necessary

Do **not** merge/deploy V5 wholesale.

Known stale V5 assumptions that must not return:
- `solRolloverTokens: 80000`
- `nativeDeltaMaxExchanges: 0`

1.2.1 acceptance:
- normal warm Sol remains same thread
- genuine rollover creates one new Sol thread
- new thread receives bounded ~20k canonical Sol history
- pre-rollover canary is recallable
- full old transcript is not replayed
- cross-model cap remains 20
- no repeated session churn
- cache remains healthy

## 1.2.2 - config/plugin cleanup

Goal: simplify Forge into a deterministic Discord wake/router + continuity transport + deterministic enforcement layer.

This is an audit release, not a bulk deletion.

For every candidate field/path produce:
- purpose
- current runtime references
- live value
- KEEP / REMOVE / MERGE recommendation
- rationale
- migration risk
- regression tests
- explicit approval before removal

Candidate areas:
- `promptMode`
- `injectReasonContext`
- old assistance/moderation prompt-construction settings
- old review-guidance plumbing
- prompt-context staging/verification state used only by removed monitor prose
- stale operator-facing moderation scoring config
- stale `maxStaffNoteChars` / `staffAlertChannelId` semantics
- old config UI wording around warnings/staff alerts
- legacy continuity handoff/rendering paths
- obsolete rollback/disposable-run machinery after 1.2.0 is source-integrated
- Sentry-era leftovers
- native-delta compatibility fields
- duplicated constants that should have one authority

Must preserve unless separately approved:
- mention/reply routing
- Sol/Luna route selection
- cross-channel spam/scammer deletion
- quarantine/review-role application
- evidence/staff reports
- configured repeat-spam ladder
- allowed timeout limits
- wrong-review rejection
- delete/kick/ban restrictions
- dedupe
- journal/ACK
- activity/logging

## Long-term implementation rule

Move these runtime behaviours into maintained TypeScript/source with regression tests and normal builds.

The 1.1.9 banked PowerShell/compiled-JS patch scripts are recovery and investigation evidence, not the desired permanent architecture.
