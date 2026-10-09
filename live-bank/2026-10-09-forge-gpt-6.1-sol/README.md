# Forge GPT-6.1 Sol production checkpoint — 2026-10-09

This directory records the accepted Forge production migration to GPT-6.1 Sol.

## Accepted production stack

- OpenClaw: 2026.7.1 / commit 2d2ddc4
- Agent runtime: Codex app-server
- Codex runtime: official 0.159.3 Windows x64
- Default model: openai/gpt-6.1-sol
- Forge runtime cap: 272000 context tokens
- Ambient sidecar: openai/gpt-5.6-luna

## Scope of the compatibility work

GPT-6.1 Sol support did **not** require changes to the Forge Discord gateway plugin,
Sentry, moderation middleware, or other Animeleague plugins.

The enablement work was confined to the OpenClaw/Codex integration layer:

1. three compiled OpenClaw runtime files were replaced with accepted Forge candidate versions;
2. official Codex 0.159.3 was installed at a stable runtime location;
3. GPT-6.1 Sol was explicitly registered because the July OpenClaw static model catalog predates it;
4. Codex app-server used the Windows unelevated sandbox mode;
5. existing Forge continuity, revert, cache, transient-context and Luna-sidecar behaviour was retained and verified.

Later changes in Animeleague/forge-discord-gateway alter **which Discord traffic is routed
to Sol or Luna**. They are not required for GPT-6.1 itself to function.

## Future OpenClaw upgrades

A future OpenClaw release with native GPT-6.1 and sufficiently new Codex support should remove
the need for the July model-catalog shim and manual Codex runtime replacement.

Do not assume every Forge patch can then be removed. Revalidate:

- exact-turn thread revert behaviour;
- durable Sol / transient Luna continuity;
- transient Discord room-context cleanup;
- native-tool permissions and Windows sandboxing;
- current-turn image/tool stability;
- cache reuse and no staircase;
- actual-input rollover behaviour.

The future goal is to remove obsolete compatibility shims while preserving Forge-specific
behavioural guarantees.

## Privacy / repository policy

Do not commit OAuth material, live openclaw.json, private Discord transcripts, rollout JSONLs,
or third-party Codex binaries.
