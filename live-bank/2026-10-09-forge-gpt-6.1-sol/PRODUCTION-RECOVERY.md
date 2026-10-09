# Forge GPT-6.1 Sol production recovery notes

Checkpoint date: 2026-10-09

## Recovery principle

Prefer the verified deployment/rollback artifacts created during the migration. This document
records the accepted invariants and fingerprints so a future operator can determine whether they
are rebuilding the same state.

## Accepted runtime invariants

- OpenClaw 2026.7.1 / commit 2d2ddc4
- official Codex 0.159.3 Windows x64
- default high-intelligence model: openai/gpt-6.1-sol
- ambient sidecar: openai/gpt-5.6-luna
- GPT-6.1 Forge runtime cap: 272000 context tokens
- Codex harness winner; no model fallback
- Windows sandbox mode: unelevated / RestrictedToken
- full Gateway startup polling budget: 120 seconds

Known successful Gateway startup observations during the migration were approximately 81 seconds
for stage and 58 seconds for final switch. A 10–15 second health timeout is a known false-failure
mode.

## Rollback layers

1. **Fast model rollback** — restore the proven stage configuration. This leaves the accepted
   OpenClaw/Codex runtime in place and returns the default to GPT-5.6 Sol.
2. **Exact pre-upgrade rollback** — use the verified Phase 1F rollback bank to restore the complete
   pre-upgrade runtime/config state.

Do not reconstruct the exact baseline from prose if the verified rollback bank is available.

## Verification after rebuild or rollback

Require:

1. Gateway deep health.
2. expected OpenClaw version for this checkpoint.
3. runtime hashes match HASH-MANIFEST.txt.
4. official Codex executable/tree fingerprints match the manifest.
5. intended default model wins through the Codex harness with no fallback.
6. native read/tool canary succeeds under the unelevated Windows sandbox.
7. Sol/Luna continuity works in both directions.
8. live Discord/DM traffic returns through the expected route.
9. transient room context is not durably accumulated.
10. per-turn input does not staircase.

## Post-switch acceptance evidence

The real production rollout sample showed:

- GPT-6.1 Sol on actual Discord turns;
- no fallback or explicit model-task failures;
- fixed 57,728-token warm Sol cached prefix across consecutive turns;
- roughly 96% cache reuse on warm Sol traffic;
- normal small per-turn growth instead of cross-turn staircase;
- paginated rollout files represented linked history pages rather than independent session growth;
- previous transient Discord room snapshots were reverted and not retained as durable history.

The 100k actual-input rollover protection remained installed and pre-production proven, but the
post-switch real-world sample had not naturally reached that threshold yet.

## Future OpenClaw upgrade

If a newer OpenClaw release natively supports GPT-6.1 and a sufficiently new Codex runtime, prefer
that native path. The compatibility shim should not be carried forward by default.

However, first reproduce Forge's behavioural guarantees: exact-turn revert, continuity, transient
context cleanup, tool permissions, sandboxing, cache stability, image/tool handling and rollover.
