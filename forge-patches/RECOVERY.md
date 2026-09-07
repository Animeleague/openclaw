# Forge recovery runbook — OpenClaw 2026.7.1

This file is for an AI rebuilding the Forge-specific OpenClaw runtime from a clean OpenClaw **2026.7.1** installation.

## Rules

- Confirm `openclaw --version` is exactly `2026.7.1` before doing anything.
- For every installer, run its status/dry-check mode first. Apply only when the script reports the expected ready state.
- If a hash, marker, source-shape, or prerequisite check fails, stop. Do not edit around the guard.
- Preserve the backup/manifest created by every patch.
- Roll back in reverse installation order.
- Do not put private Forge data in this public repository.
- The live Forge runtime uses the **project-local `@openclaw/codex` bundle** under `~/.openclaw/npm/projects/...`, not a stale global Codex bundle. Patches that target Codex turn assembly must prove they are modifying the executable project-local runtime.

## Canonical installation order

1. `Patch-ForgeCodexStableToolCatalogV2.ps1`
   - final marker: `FORGE_CODEX_STABLE_TOOL_CATALOG_V2`
   - stabilises inert durable tool specs across owner/non-owner turns; real current-turn authorisation remains authoritative.

2. `Patch-ForgeCodexTurnPayloadDiagV1.ps1`
   - marker: `FORGE_CODEX_TURN_PAYLOAD_DIAG_V1`
   - **reproduction prerequisite only**: observation-only diagnostic required by the proven Durable Registration V1.1 baseline.

3. `Patch-ForgeCodexTransientLunaV1.ps1`
   - marker: `FORGE_CODEX_TRANSIENT_LUNA_V1`
   - **lineage prerequisite only**: install because Dual Warm Threads V2.1 upgrades this exact verified state. Do not leave V1 as the final model-switch behaviour.

4. `Patch-ForgeCodexDualWarmThreadsV2_1.ps1`
   - final marker: `FORGE_CODEX_DUAL_WARM_THREADS_V2_1`
   - Sol/Terra remains the durable binding; Luna uses a parked in-memory sidecar; repeated Luna resumes the sidecar; returning Sol resumes the durable thread.

5. `Patch-ForgeCodexDurableRegistrationProofV1_1.ps1`
   - final marker: `FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1`
   - requires Stable Tool Catalog V2, Turn Payload Diag V1 and Dual Warm Threads V2 lineage markers.
   - durable registered schema may use the owner-capable/image-neutral form; executable current-turn tools must continue using real ownership and real current-turn images.

6. `Patch-ForgeCodexImageStabilityV1_1.ps1`
   - final marker: `FORGE_CODEX_IMAGE_STABILITY_V1_1`
   - deduplicates legacy media aliases and keeps the image-tool schema stable on image-bearing turns.

7. `forge-patches/transient-runtime-context/Patch-ForgeCodexTransientRuntimeContextV4.ps1`
   - final marker: `FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4`
   - **live-proven 2026-09-07** on the real OpenAuth / Codex app-server runtime.
   - for Discord turns, keeps the current Forge/OpenClaw runtime prefix (PERSISTENT + TRANSITORY memory, monitor/history support context and other turn scaffolding) model-visible through the existing turn-scoped developer-instructions channel.
   - persists only the final `[meta ...]` block plus actual Discord message as native user history.
   - prevents the previously observed roughly +3.1k to +3.3k token context staircase per tiny Discord turn.
   - resolves the executable project-local `@openclaw/codex` run bundle and refuses V3 `additionalContext` remnants.
   - **supersedes Context History V1/V2 and Monitor Transient Context V1.2/V1.3 for this runtime. Do not install those older carriers before or after V4.**

8. `Patch-ForgeCurrentTurnImageDedupeV1_1.ps1`
   - final marker: `FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1`
   - requires Image Stability V1.1 and removes exact duplicate image payloads at the final current-turn image merge.

9. `forge-patches/discord-inbound-compact/Patch-ForgeDiscordInboundCompactV1-FINAL.ps1`
   followed by `Patch-ForgeDiscordInboundCompactV2-CORRECTED.ps1`.
   - final marker: `FORGE_DISCORD_INBOUND_COMPACT_V2`
   - run each dry check first; V2 is an incremental upgrade of the proven V1 runtime.

10. `Patch-ForgeBootstrapToolEfficiencyV2-REMENTION.ps1`
    - dry check first, then apply if ready.
    - after application refresh Forge's backend prompt with `/reset soft`.

11. `forge-patches/kb-retrieval-efficiency/Patch-ForgeKBRetrievalEfficiencyV1.ps1`
    - workspace-policy edit only; never commit the real live `AGENTS.md` here.

Restart the gateway at the restart points printed by the scripts. A future recovery AI may batch restarts only after proving that doing so does not invalidate an installer's expected baseline; otherwise follow each script literally.

## Do not install as part of the canonical recovery

- 8k native auto-compaction headroom proof (`FORGE_CODEX_NATIVE_AUTOCOMPACT_HEADROOM_V1`).
- 200k auto-compaction proof/config (`FORGE_CODEX_AUTOCOMPACT_200K_PROOF_V1`).
- transient-runtime-context V1/V2/V3 experiments.
- **Context History V1/V2 `additionalContext` carrier** (`FORGE_CONTEXT_HISTORY_V1` / `FORGE_CONTEXT_HISTORY_V2`) — superseded by V4 for the 2026.7.1 Forge runtime.
- **Monitor Transient Context V1.2/V1.3 `additionalContext` carrier** (`FORGE_MONITOR_TRANSIENT_CONTEXT_V1`) — superseded by V4 for the 2026.7.1 Forge runtime.
- Dual Warm Threads V2 (superseded by V2.1).
- older image, bootstrap or transient-context revisions except where the sequence above explicitly requires an earlier revision as a verified baseline.

### Why the old additionalContext carriers are excluded

Live testing on 2026-09-07 proved that this local Codex version persists `additionalContext` fragments as ordinary native `role:"user"` records such as `<external_forge_runtime_context_0000>...`. That moves the staircase rather than removing it. V4 instead uses the already-existing turn-scoped developer-instructions path, which was proven to keep exactly one runtime/memory block active per turn without leaking it into durable Discord user history.

## Final verification

After installation, rerun every individual patch status command. Then verify the final runtime contains at least:

- `FORGE_CODEX_STABLE_TOOL_CATALOG_V2`
- `FORGE_CODEX_DUAL_WARM_THREADS_V2_1`
- `FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1`
- `FORGE_CODEX_IMAGE_STABILITY_V1_1`
- `FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4`
- `FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1`
- `FORGE_DISCORD_INBOUND_COMPACT_V2`

Functional smoke tests must cover Sol → Luna → Luna → Sol continuity, owner → non-owner permissions/cache stability, single/multiple images, a long history turn, a monitor-summoned turn, and ordinary Discord guild/DM metadata.

For V4 specifically, inspect native Codex rollout records after at least 6 small Discord turns and prove all of the following:

1. Durable Discord `role:"user"` records contain only `[meta ...]` plus the actual user message, with zero `# Forge Memory Context`, `PERSISTENT_MEMORY`, `TRANSITORY_MEMORY`, `<forge_current_turn_context>` or `<external_forge_runtime_context_...>` leakage.
2. Each current turn's collaboration/developer instructions contain exactly one `## Forge Current-Turn Runtime Context` block and exactly one `# Forge Memory Context` block.
3. Tiny-turn input usage no longer grows by thousands of tokens per turn. The 2026-09-07 live proof showed post-warm natural growth around +100 to +130 tokens per small Discord exchange instead of roughly +3.1k to +3.3k.
4. Warm cache reuse remains healthy; the live proof reached roughly 95–97% cached input on consecutive Luna turns.

If expected behaviour differs, stop rather than stacking another workaround.

## Separate Forge plugin

`forge-discord-monitor` is maintained in its own repository. At this checkpoint its source was v1.1.4. The outbound `@everyone` / `@here` safeguard was banked in plugin source but intentionally had not yet been built/deployed; do not assume a clean runtime contains it.
