# Forge / OpenClaw Native Context — FINAL10 Live-Proven Bank

Date: 2026-08-16
Repository: Animeleague/openclaw
Pinned OpenClaw: 2026.7.1 (2d2ddc4)
Pinned bundled Codex baseline: 0.144.3 / rust-v0.144.3 / 78ad6e6bfd1d3b6a209acd3ef82172a96b25179c

Core rule: **Chuck the tools, not the conversation.**

## Final architecture

Monitor runs use a private persistent native binding/thread. After a successful monitor turn, OpenClaw rolls back one native turn, retains the clean private binding/thread id, but releases the live in-memory Codex session. The next monitor run resumes the same clean bound thread with fresh session-scoped bookkeeping.

Genuine conversation lineage remains separate and warm. Genuine tool-bearing turns keep the existing clean pre-tool fork/restore behaviour.

## Exact artifacts / prerequisites

- `Patch-ForgeCodexNativeThreadRollbackV1.01.ps1`
  - SHA256: `6649d618cd1af5c6e5b24101792d1fc0ab361b03d35e53ed50024358c318ee72`
- `Patch-ForgeCodexMonitorProjectionBypassV1.02-FIXED.ps1`
  - SHA256: `d323c1bf9b360c66b1e05ce65668553f018e249f0357bece7f5c676d16340e4b`
- `Patch-ForgeCodexMonitorWarmRollbackV1.04-FINAL5.ps1`
  - SHA256: `f911b7f6443e5eeb28e1a0383a251518ba297af54b3b80c6869574d84ff53139`
- `Patch-ForgeCodexMonitorPreTurnRollbackV1.04-FINAL8.ps1`
  - SHA256: `0c87c026e656330e4b8ac111080d9386aea4067043aa7226175e270a418a8733`
- `Patch-ForgeCodexMonitorCleanupRollbackV1.04-FINAL9.ps1`
  - SHA256: `a57b7ca2df4d798ed1152beccbc07badcb91780e23ab34d9c02d42ae7c65c789`
- `Patch-ForgeFINAL10-MonitorRollbackReleaseLive-EXACT-FIXED.ps1`
  - SHA256: `8e9d8a61833463b04ec0ac32a051b7eb4dc3752915dcfe6a15e5456993d8c7b4`
  - FINAL10 patch wrapper used for the successful live proof.

Exact FINAL9 live-proven baseline before FINAL10:
- lifecycle SHA256: `e5ce34aee1adfa839f65044d6654442c2c35f11b6a7ff9cac20d7caa5d4c359e`
- run-attempt SHA256: `47a84fbb1f5c54b3d8d070b3d00ea369df69a14df0e456443fbb7449cf46da6a`

## FINAL10 proof

After restart, Luna monitor runs used the same native thread:
`01a00804-736a-72a3-98e5-08d496cbb5cd`

Observed usage:

- cold: fresh 35933 / cache 0
- warm: fresh 689 / cache 35584
- warm: fresh 1163 / cache 35584
- warm: fresh 573 / cache 36608
- warm: fresh 975 / cache 36608
- warm: fresh 1472 / cache 36608

The rolling Discord context grew 753 -> 840 -> 930 -> 1017 -> 1214 chars while cache remained flat across multiple turns, with only one discrete +1024 cache-prefix extension. The prior pathological per-turn +9216 / +4k-5k native staircase was eliminated.

## Rejected designs

Do not reintroduce:
- persistent dirty-model/session => fresh-next-turn semantics
- transient-tools v0.1.14
- `Patch-ForgeCodexNativeThreadPolicyV1.ps1`
- V1.10 post-rollback diagnostic; it perturbed the cleanup seam and recreated the staircase.

Bank this exact proven state before any cleanup/refactor or source-level upstreaming.
