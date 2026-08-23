# Codex Hot Direct Tools v1 - Live-Proven Bank

Status: LIVE-PROVEN on Forge/OpenClaw OpenAuth/Codex app-server path
Date: 2026-08-23
Branch: codex-hot-direct-tools

## Purpose

Keep Forge's three common operational tools directly callable in the initial Codex app-server tool surface while leaving the wider OpenClaw catalogue deferred/searchable.

Hot direct tools added:

- `message`
- `web_fetch`
- `web_search`

Existing direct control tools retained:

- `agents_list`
- `sessions_spawn`
- `sessions_yield`

The intended source change is stored in `patches/codex-hot-direct-tools-v1.patch` and applies only to `extensions/codex/src/app-server/dynamic-tools.ts`.

## Live runtime tested

Forge was verified specifically on the OpenAuth/Codex app-server execution path, not the generic API/embedded-agent path.

Live package:

- OpenClaw: `2026.7.1`
- `@openclaw/codex`: `2026.7.1`
- Codex app-server project: `openclaw-codex-8902d781d4`

The actual Forge project-local Codex bundle was patched after confirming the Gateway-spawned app-server process loaded from that project.

Known-good bundle bank SHA256 before patch:

`2EF1B27FFA4406FC378796C54A285EB2E4417A5D95F0C98970A233A9FE5FB58C`

Live-proven patched bundle SHA256:

`1B618A4B4A4F11B33DDDA59D5D0F19789E23DF2407BBE3C8EA1B93849D4EC628`

## Validation results

Fresh `/new` Codex session after Gateway restart showed:

- `message` exposed as a top-level direct function
- `web_search` exposed as a top-level direct function
- `web_fetch` exposed as a top-level direct function
- deferred `openclaw` namespace reduced from 32 to 29 tools

Direct execution tests:

- `tools.message(...)` - PASS
- `tools.web_search(...)` - PASS
- `tools.web_fetch(...)` - PASS

Natural-language validation:

- Forge was asked to find the latest information about London Anime & Gaming Con without tool instructions.
- Forge selected `tools.web_search(...)` directly.
- No `ALL_TOOLS` execution occurred.
- No tool-discovery call was required before the direct web tool.

This removes the previously observed discovery blowout for these common paths while keeping uncommon tools deferred.

## Observed token behaviour

The direct-tool tests stayed around the normal active-context range instead of reproducing the previous discovery explosion. Earlier ALL_TOOLS discovery had emitted a result reporting 18,704 original tokens and caused large subsequent input growth. The hot-direct path avoided that discovery step.

The later natural-language research turn still grew substantially because Forge over-researched the question. That is a separate minimum-sufficient-tool-usage problem and is intentionally not part of this patch.

## Scope guardrails

Do not broaden this patch to:

- `browser`
- `cron`
- the entire OpenClaw tool catalogue
- `codexDynamicToolsLoading: "direct"`
- generic API/embedded-agent paths
- Transient Tools

The value of this change is the deliberately small hot set.

## Next integration step

Apply the source patch to the branch source, add/update focused Codex dynamic-tool regression tests, run the targeted Codex app-server test suite, then review the diff before any merge to `main`.
