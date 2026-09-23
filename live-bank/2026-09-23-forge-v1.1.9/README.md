# Forge 1.1.9 live bank - 2026-09-23

Status: **BANKED STABLE BASELINE WITH KNOWN DEFERRED RUNTIME ISSUES**

This folder records the exact Forge/OpenClaw 1.1.9 state accepted for production banking on 23 September 2026.

It intentionally freezes a useful, stable release instead of continuing to stack ad-hoc compiled-bundle hotfixes onto 1.1.9.

## Exact accepted live state

OpenClaw runtime:
- OpenClaw version: `2026.7.1`
- bank branch base: current `main` at bank time, including the already-banked Forge BOOTSTRAP runtime patch
- active Codex bundle path on the live Windows host:
  `%USERPROFILE%\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist\run-attempt-FUyOjGCV.js`
- accepted live Codex SHA-256:
  `87abfb4183bba56ffd9c6f345c405dea9083b5990172d3cbac059827fb5bcded`
- accepted runtime patch level: `v1i`
- temporary Sol rollover threshold: `200000` tokens
- shared native-delta / cross-model handoff cap: `20` exchanges

Forge Discord Monitor:
- live-proven silent-monitor source head:
  `ebf4acd23d0bbca2a2fec1edd4a0292bfb9e96f6`
- merged to monitor `main` via PR #21 on 2026-09-23
- monitor merge commit:
  `4373ac8dccb65925f814d00772f341b3d1c2b028`
- live candidate ZIP SHA-256:
  `aea37af4153a582d5327561fa2a5e2ad342b7bffa145c0ae0c2b09856acad111`
- embedded monitor TGZ SHA-256:
  `1fe3674b6a50a6f2e6b3694e4971a7f02ea79e6086913bf16dbc2572b58f2e69`

Full pre-silent rollback snapshot retained on the live host:
`C:\Users\PC User\Desktop\forge-pre-silent-v119-20260922-131951`

## What 1.1.9 fixes and preserves

### Monitor / Discord routing

- removes model-facing monitor behavioural prompt prose
- removes legacy Sentry-era prompt markers from monitor context
- keeps monitor wake/context transport neutral rather than acting as a second personality/policy layer
- preserves mention/reply routing behaviour
- preserves deterministic anti-spam/scammer handling
- preserves deterministic moderation enforcement
- model-facing `alert_staff` tool removed
- warn/timeout actions can still generate deterministic staff reports when enabled
- moderation scores/triggers/reasons are not exposed to the model

### Native continuity

- Sol -> Luna persistent/native continuity retained
- Luna -> Sol persistent/native continuity retained
- shared native handoff cap is 20
- per-native-thread dedupe and bounded ACK/recovery handling retained
- Discord chronology/provenance is neutral
- old model-facing private-DM warning prose is not carried in continuity payloads
- Luna sidecar reuse remains intact
- ordinary native conversation retention remains intact

### BOOTSTRAP / speaking behaviour

The already-banked BOOTSTRAP runtime patch remains part of the accepted baseline:
- BOOTSTRAP owns runtime plumbing and hard transport contracts
- AGENTS.md owns social/support judgement
- exact `NO_REPLY` remains the transport-level silence contract
- open-room conversation does not require a direct mention when AGENTS permits a reply
- DM behaviour remains separate from group-channel silence rules

### Stability observed before bank

After reverting the failed v1m experiment back to exact v1i:
- Luna completed repeated normal turns without new harness/runtime failures
- cross-channel Luna recall worked between `football-sports` and `gaming-zone`
- Luna retained the `pineapple` continuity canary
- Sol picked up the same continuity in DM
- Sol returned from DM to a public mentioned channel and replied normally
- no recurrence of the v1m `ReferenceError`

Warm Sol cache behaviour was especially strong:
- input 130,763 -> first observed cold/uncached turn
- 130,941 input / 130,560 cached
- 131,015 input / 130,816 cached
- 131,101 input / 130,816 cached
- warm native growth only +178, +74, +86 tokens
- roughly 99.7-99.85% cache reuse on those warm turns

Luna caching was also healthy, but its native input still grows too quickly because of the known room-history persistence issue described below.

## Known limitations accepted in 1.1.9

These are **not fixed** and must not be represented as fixed.

### 1. Luna latest-10 is still durable

The rolling room snapshot that is intended to be current-turn context still ends up in durable Luna native history.

Observed Luna input growth remains roughly:
- +700 to +1,100 tokens per ordinary turn
- typical recent sample: +814, +1,127, +787, +788, +787, +733

This is stable/bounded and cache-friendly, but wasteful.

### 2. Luna exact NO_REPLY native cleanup is not solved

Exact `NO_REPLY` correctly suppresses visible Discord output, but the native-history cleanup path is not reliable in v1i.

Do not claim silent turns are fully removed from effective native history.

### 3. Sol transient latest-10 delivery is not solved

The monitor/OpenClaw path can construct and verify room context at an earlier hook, but prior testing proved that this does not guarantee the latest-10 reaches the actual Sol model/provider input.

Early `verified:true` diagnostics are not proof of model receipt.

### 4. v1m must not be deployed

The v1m experiment attempted to make the existing V7 rollback/reinject transaction own Luna monitor-turn cleanup.

It failed live because a transaction-local variable was referenced after its lexical block:

`ReferenceError: forgeTxnMonitorExactNoReplyV119M is not defined`

The model still generated sensible replies, but the post-turn exception prevented Discord delivery.

More importantly, the investigation also showed that the V7 clean transaction was not actually armed for the tested Luna monitor turns: finalizer diagnostics had `monitor:true` but lacked the expected transaction `toolThreadId/toolTurnId` state.

Therefore the remaining fix is not just a one-line monitor guard removal. It needs a clean source-level redesign/test of transaction arming and finalization.

The exact v1m script is banked under `reference-only/` for investigation only.

## Release boundary

**1.1.9 is frozen here.**

Do not add more compiled-bundle letter hotfixes to this release unless restoring this exact accepted state.

The next work begins from this bank and belongs to 1.2.x.

See `ROADMAP-1.2.x.md` for the full planned sequence.
