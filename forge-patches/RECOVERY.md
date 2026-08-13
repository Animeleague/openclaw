# Forge recovery runbook — OpenClaw 2026.7.1

This file is for an AI rebuilding the Forge-specific OpenClaw runtime from a clean OpenClaw **2026.7.1** installation.

## Rules

- Confirm `openclaw --version` is exactly `2026.7.1` before doing anything.
- For every installer, run its status/dry-check mode first. Apply only when the script reports the expected ready state.
- If a hash, marker, source-shape, or prerequisite check fails, stop. Do not edit around the guard.
- Preserve the backup/manifest created by every patch.
- Roll back in reverse installation order.
- Do not put private Forge data in this public repository.

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

7. `Patch-ForgeCodexContextHistoryV1.ps1`
   - marker: `FORGE_CONTEXT_HISTORY_V1`
   - moves duplicated historical `<conversation_context>` out of durable user text and into chunked untrusted `additionalContext`.

8. `forge-patches/context-history/Patch-ForgeCodexContextHistoryV2.ps1`
   - final marker: `FORGE_CONTEXT_HISTORY_V2`
   - install immediately after V1.
   - V2 keeps the V1 carrier intact and changes only the guard so the carrier runs whenever `promptContextRange` exists, including with an external context engine.

9. `Patch-ForgeMonitorTransientContextV1_2-FAST.ps1`
   - marker: `FORGE_MONITOR_TRANSIENT_CONTEXT_V1`
   - keeps monitor review scaffolding model-visible for the current inference without persisting it as ordinary durable user-history text.

10. `Patch-ForgeMonitorTransientContextV1_3.ps1`
    - incremental upgrade of step 9.
    - final matcher prefix is `[Forge Discord Monitor`.

11. `Patch-ForgeCurrentTurnImageDedupeV1_1.ps1`
    - final marker: `FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1`
    - requires Image Stability V1.1 and removes exact duplicate image payloads at the final current-turn image merge.

12. `forge-patches/discord-inbound-compact/Patch-ForgeDiscordInboundCompactV1-FINAL.ps1`
    followed by `Patch-ForgeDiscordInboundCompactV2-CORRECTED.ps1`.
    - final marker: `FORGE_DISCORD_INBOUND_COMPACT_V2`
    - run each dry check first; V2 is an incremental upgrade of the proven V1 runtime.

13. `Patch-ForgeBootstrapToolEfficiencyV2-REMENTION.ps1`
    - dry check first, then apply if ready.
    - after application refresh Forge's backend prompt with `/reset soft`.

14. `forge-patches/kb-retrieval-efficiency/Patch-ForgeKBRetrievalEfficiencyV1.ps1`
    - workspace-policy edit only; never commit the real live `AGENTS.md` here.

Restart the gateway at the restart points printed by the scripts. A future recovery AI may batch restarts only after proving that doing so does not invalidate an installer's expected baseline; otherwise follow each script literally.

## Do not install as part of the canonical recovery

- 8k native auto-compaction headroom proof (`FORGE_CODEX_NATIVE_AUTOCOMPACT_HEADROOM_V1`).
- 200k auto-compaction proof/config (`FORGE_CODEX_AUTOCOMPACT_200K_PROOF_V1`).
- `transient-runtime-context` experiments.
- Dual Warm Threads V2 (superseded by V2.1).
- older image, bootstrap, Context History or Monitor Transient Context revisions except where the sequence above explicitly requires an earlier revision as a verified baseline.

## Final verification

After installation, rerun every individual patch status command. Then verify the final runtime contains at least:

- `FORGE_CODEX_STABLE_TOOL_CATALOG_V2`
- `FORGE_CODEX_DUAL_WARM_THREADS_V2_1`
- `FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1`
- `FORGE_CODEX_IMAGE_STABILITY_V1_1`
- `FORGE_CONTEXT_HISTORY_V2`
- `FORGE_MONITOR_TRANSIENT_CONTEXT_V1`
- `FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1`
- `FORGE_DISCORD_INBOUND_COMPACT_V2`

Functional smoke tests must cover Sol → Luna → Luna → Sol continuity, owner → non-owner permissions/cache stability, single/multiple images, a long history turn, a monitor-summoned turn, and ordinary Discord guild/DM metadata. If expected behaviour differs, stop rather than stacking another workaround.

## Separate Forge plugin

`forge-discord-monitor` is maintained in its own repository. At this checkpoint its source was v1.1.4. The outbound `@everyone` / `@here` safeguard was banked in plugin source but intentionally had not yet been built/deployed; do not assume a clean runtime contains it.
