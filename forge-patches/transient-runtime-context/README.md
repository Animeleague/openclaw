# Forge Codex Transient Runtime Context V4

Live-proven against the Forge OpenAuth / Codex app-server runtime on OpenClaw **2026.7.1** on 2026-09-07.

## Problem

Forge injects a substantial current-turn support block on Discord turns, including PERSISTENT memory, TRANSITORY memory, monitor/history context and other runtime scaffolding. The live Codex integration was passing that decorated text as ordinary native user input. Codex persisted each copy into native conversation history, creating a context staircase of roughly **+3.1k to +3.3k tokens per tiny Discord turn** and causing frequent compactions/thread rebuilds.

An attempted V3 carrier using Codex `additionalContext` was rejected after live proof showed this local Codex version persisted each fragment as native `role:"user"` records named `<external_forge_runtime_context_....>`. V3 must not be reinstalled.

## V4 behavior

For Discord turns only, V4 finds the final `\n[meta ` boundary in the fully assembled OpenClaw prompt.

- Everything before the final `[meta ...]` boundary remains model-visible for the current inference through the existing **turn-scoped developer instructions** channel.
- `[meta ...]` plus the actual Discord message remains the ordinary native user input.
- The current-turn Forge runtime block is replaced each turn rather than appended.
- Non-Discord flows fall back to existing behavior.

Marker: `FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4`

## Live proof

Native rollout inspection after the patch showed:

- `RuntimeBlocks = 1` on every tested turn.
- `MemoryBlocks = 1` on every tested turn.
- zero Forge PERSISTENT / TRANSITORY / runtime-context leakage into durable Discord `role:"user"` history.
- durable Discord user records were approximately 166-218 chars (`[meta ...]` plus the actual message).
- consecutive tiny Luna turns used approximately 16,520, 16,648, 16,765, 16,898 and 17,022 input tokens instead of the previous +3k-per-turn staircase.
- once warm, cached input remained around 95-97% on the tested sequence.

The remaining roughly +100-130 tokens of natural growth per small Discord exchange is a separate optimisation target. Do not mix that work into V4.

## Recovery

Run status first:

```powershell
.\forge-patches\transient-runtime-context\Patch-ForgeCodexTransientRuntimeContextV4.ps1 -Mode Status
```

Apply only if it reports `STATUS: READY TO APPLY`:

```powershell
.\forge-patches\transient-runtime-context\Patch-ForgeCodexTransientRuntimeContextV4.ps1 -Mode Apply
openclaw gateway restart
```

Rollback:

```powershell
.\forge-patches\transient-runtime-context\Patch-ForgeCodexTransientRuntimeContextV4.ps1 -Mode Rollback
openclaw gateway restart
```

## Important

Do **not** stack the old Context History V1/V2 or Monitor Transient Context `additionalContext` carrier patches on top of V4. Those older recovery steps are superseded for this 2026.7.1 Forge runtime.
