# Forge Stage 2 Luna native delta continuity - 15 September 2026

## Status

LIVE-PROVEN on Forge's Windows OpenClaw OpenAuth / Codex app-server path.

Canonical OpenClaw bank branch:

`bank/2026-09-15-stage2-luna-native-delta-live`

Predecessor:

`bank/2026-09-12-sol-luna-continuity-120k-live`

Matching monitor bank:

- Repository: `Animeleague/forge-discord-gateway`
- Branch: `bank/2026-09-15-stage2-luna-native-delta-live`
- Tag: `bank-2026-09-15-stage2-luna-native-delta-live`
- Commit: `70cc448`

## Stage 2 goal

Preserve the dual-warm architecture while giving Luna real native conversational continuity for completed public Sol turns that happened while Luna was not participating.

Architecture remains:

- Sol: durable principal native Codex thread
- Luna: separate warm sidecar native Codex thread
- newest 10 same-channel Discord messages: transient current-turn context for both
- missed completed public Sol exchanges: injected into Luna native history once
- no rollback
- no fork-per-turn
- no new Luna thread on normal model switches
- no DM/private/staff-only content injected into Luna native history

## Live markers

Monitor:

`FORGE_CROSS_MODEL_NATIVE_DELTA_V1`

Codex:

`FORGE_CODEX_NATIVE_DELTA_V1`

Existing continuity markers retained:

- `FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4`
- `FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4`
- `FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3`
- `FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1`
- `FORGE_CODEX_LUNA_NEVER_DURABLE_V1`

## Implementation

The monitor publishes a run-bound native Luna delta through the shared process symbol:

`Symbol.for("forge.codex-native-delta.v1")`

The Codex run-attempt bundle consumes it only when the resolved model leaf is `gpt-5.6-luna`.

Immediately before the live `activeTurnRoute.armTurn()` / `turn/start` sequence, Codex:

1. validates a public-discord payload
2. resolves the active warm Luna thread
3. filters exchange IDs already injected into that exact thread
4. calls `thread/inject_items` with native user/assistant message pairs
5. marks delivery only after the request resolves
6. writes confirmation back to the monitor bridge

The monitor ACKs the pending source IDs only after the Luna reply succeeds and the exact confirmation set matches.

This gives retry safety without replaying the same Sol exchanges every Luna turn.

## Privacy boundary

Native injection is persistent, so it is deliberately narrower than transient room context.

Eligible Sol source exchanges must be:

- group/public traffic
- explicitly `nativeLunaEligible === true`
- not in `routingGate.alwaysDispatchChannelIds`
- not in `excludedChannelIds`

The Codex bridge independently requires:

- `scope: "public-discord"`
- each exchange `visibility: "public"`

Legacy exchanges lacking explicit eligibility are ignored.

DM/private content is never injected into Luna native history.

## Static validation

Monitor tests after Stage 2 patch:

- 121 tests
- 121 pass
- 0 fail

New tests include:

- newest 30 eligible public Sol exchanges are selected deterministically
- overflow IDs are ACKed on successful bounded sync
- DM/private/staff-ineligible exchanges are excluded
- legacy principal exchanges without explicit native eligibility are ignored

## Live proof

Gateway restart loaded the new monitor package and retained the Codex live bridge.

Installed monitor package shasum:

`5f77929f9de685eaa4035b6604e89e38e5041311`

Codex Stage 1 protected pre-patch SHA256:

`0EB6C786C7C6AE91E4DBAB882364BC7AC7BEF01C72DC22E1FBB19452E641406C`

Codex Stage 2 live SHA256:

`3C2B2487D111680FC6DC53AEEBBE2BE3FA75FE11DAF08398C571769188169A3B`

Post-restart Stage 2 markers remained present in the live run-attempt bundle.

### Canary proof

Public Sol exchange:

`Stage 2 continuity canary is 58310472`

The subsequent Luna rollout contained a native user `response_item` beginning:

`[Missed completed Discord exchange | ... continuity-id f289ee28-3cdc-443d-8bed-3e4c41df48c8]`

and containing the canary.

Luna then answered:

`58310472`

Tool-call rows in that Luna rollout:

`0`

Exact native injected copies of that continuity ID in the Luna rollout:

`1`

Therefore the canary was available as actual Luna native conversation history, not only transient previous-channel context or a lookup tool, and it was not replayed twice.

## Threads observed during proof

Post-restart Luna:

`01a0a6d7-e71e-7113-99e4-15ef32a86d05`

Post-restart Sol:

`01a0a68c-4d3b-71d0-9838-6d6bee8dc2fc`

The restart intentionally created a fresh Luna sidecar lifecycle; ordinary model switching must continue to reuse the active sidecar.

## Rollover policy

The proven V4 completed-turn clean rollover remains at 120,000 native tokens.

Stage 2 does not alter rollover semantics.

Keep:

- `historyCoveredThrough`
- `thread_bootstrap`
- compact fresh baseline
- no full durable transcript replay

The 120k cap remains intentionally temporary while context/tool overhead is still being measured.

## Canon installer

Use:

`live-bank/2026-09-15-stage2-luna-native-delta-live/Patch-ForgeStage2CodexLive-v2.ps1`

It is fail-closed, checks the protected Stage 1 SHA before first application, validates prerequisite markers and the exact compiled turn-start anchor, creates a timestamped backup, runs `node --check`, and restores the backup on failure.

## Next work

Core continuity plumbing is now considered complete enough to freeze.

Next work should focus on:

1. session/token/cache analysis
2. context overhead reduction
3. tool-result size/transience
4. KB retrieval and selective older-context access
5. model/tool/memory quality improvements

Do not reintroduce per-turn `thread/rollback` for Luna continuity.
