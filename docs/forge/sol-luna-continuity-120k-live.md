# Forge Codex continuity baseline - 12 September 2026

## Status

Live-proven on Forge's real Windows OpenClaw OpenAuth / Codex app-server path.

Canonical bank branch:

`bank/2026-09-12-sol-luna-continuity-120k-live`

Predecessor:

`bank/2026-09-09-clean-rollover-60k-live`

## Canonical model-binding policy

Forge uses separate warm GPT-5.6 bindings:

- Sol/Terra: durable principal conversation thread
- Luna: isolated sidecar/transient thread

A model switch is not a reason to rotate the principal Sol thread.

The principal Sol thread must survive:

`Sol -> Luna -> Sol -> Luna -> Sol`

with the same Sol thread ID.

## Regression fixed

Monitor Warm Rollback V1.04 FINAL5 previously ran after Dual Warm Threads V2.1 and reset the Luna-sidecar decision. A Luna turn could therefore patch the live Sol binding's model metadata to Luna. On the next Sol turn, native GPT-5.6 version mismatch logic cleared the binding.

The fix makes model isolation authoritative:

- `FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1`
- `FORGE_CODEX_LUNA_NEVER_DURABLE_V1`

Monitor rollback is a transient-turn policy layered on top of model isolation. It must never disable Dual Warm isolation.

A fresh Luna call after gateway restart also cannot claim the durable principal binding.

## Live proof

Principal Sol thread:

`01a09787-d014-7393-afe3-c90eb8763240`

Observed after clean binding:

- Luna interleaved successfully
- Sol resumed the exact same thread
- zero destructive `rotating a GPT-5.6 multi-agent thread binding` operations
- room switch general-chat -> DM -> general-chat preserved immediate context

Separate Luna threads were also proven active:

- `01a09788-6eb0-7bb1-a3ad-1ff350f0cbfa`
- `01a09797-63b3-7381-90df-68eb2083cf47`

This proves the fix does not route all traffic to Sol.

## Staircase/cache sanity

The old approximately +3k-per-message context staircase is not present.

Healthy Sol principal growth during the proof was typically around +94 to +145 tokens on short turns, with longer answers producing proportionally larger deltas.

Warm Sol cache was approximately 99.2-99.6%.

Warm Luna cache was generally approximately 91-98%.

Always inspect Codex `last_token_usage` for per-turn growth. `total_token_usage` is cumulative and will produce a false staircase if differenced incorrectly.

## Rollover policy

The completed-turn clean rollover cap is temporarily set to 120,000 native tokens.

This retains the proven V4 clean rollover mechanism:

- completed native token count
- `historyCoveredThrough`
- `thread_bootstrap`
- compact fresh baseline
- no full durable transcript replay

The threshold was raised from 60k because a native rollover loses more immediate warm-thread conversational continuity than originally assumed. Keep 120k while native tool-output and baseline-context optimisation are unfinished.

For a healthy principal conversation, model switching must not rotate the native thread. Age/size rotation is controlled by the completed-turn hardcap.

Exceptional safety rotations remain valid for explicit reset, incompatible runtime/config state, or unrecoverable native context failure.

## Canon installer

Use:

`live-bank/2026-09-12-sol-luna-continuity-120k-live/Patch-ForgeCodexContinuityLive-20260912.ps1`

The installer is fail-closed, backs up both active bundles, validates prerequisite markers, runs `node --check`, and restores backups on failure.

## Next work

Do not lower the cap back to 60k until tool/context optimisation has been re-measured.

Next optimisation targets:

1. transient native tool-result removal / rollback policy
2. tool-output size reduction
3. baseline prompt/context reduction
4. routing-cost audit
