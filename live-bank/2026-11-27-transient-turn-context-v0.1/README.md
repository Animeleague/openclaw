# OpenClaw Transient Turn Context

**v0.1 — live-demonstrated local-model proof of concept; generic naming derivative of the tested checkpoint.**

## Why this exists

A conversational agent needs two distinct kinds of history: durable user/assistant conversation, and disposable context for the current request. The latter includes recent room messages, reply targets, sender/channel metadata, timestamps and current-turn instructions. It is useful now, but should not accumulate as another permanent model-visible transcript entry on every interaction.

OpenClaw 2026.11.10 (build 6ea542f) retained historical runtime-context carriers on the tested OpenAI-compatible local route to favour append-only prefix caching. Even very short chat exchanges grew the prompt by approximately 1,100 tokens each. Overlapping Discord history snapshots and repeated instructions consumed context without adding comparable useful memory. Large context windows or inexpensive hosted models can obscure the problem; a 32k local model exposes it quickly.

The objective is to retain genuine conversational continuity, reuse the stable cached prefix and refresh a bounded current-turn snapshot without replaying every previous snapshot.

## What this plugin does

The configured custom local provider's existing `buildReplayPolicy` hook sets `appendOnlyRuntimeContext: false`. All other fallback replay-policy values for the tested route are preserved. OpenClaw's existing typed-carrier filter at the inference boundary excludes historical runtime context while keeping the current carrier.

No core patch, transcript deletion, session reset, model replacement, tool-permission change or reasoning configuration change is required. Recent Discord history remains available in the current request; the test retained a five-message lookup. This is a replay-projection change, not physical deletion of historical records.

## Measured live results

Tested on Windows with OpenClaw 2026.11.10 (6ea542f), LM Studio, reasoning-enabled Gemma via OpenAI Completions and a 32,768-token context window. The same Discord session continued through activation. Evidence: raw model prompts, prediction statistics, session snapshots and inference-server logs.

| Metric | Before | After |
|---|---:|---:|
| Runtime-context carriers in sampled prompts | 6–9 | 1 |
| Input tokens immediately before/after activation | 14,805 | 6,381 |
| Mean input growth per sampled short exchange | 1,080 | 211 |
| Mean fresh tokens per warm request | 1,092 | 1,216 |
| Mean warm cache-hit fraction, derived | 92.0% | 82.2% |
| Recent room recall | Working | Passed live canary |

The sampled prompt shrank by 56.9%, and sampled input growth fell by approximately 80.5%. Previous actual conversations survived. The bot correctly recalled three numbers posted in the room without addressing it. The subsequent prompt still had only one runtime-context carrier.

KV caching **remains functional**, not unchanged: post-fix warm requests reused approximately 82% of their input. Fresh evaluation increased slightly; no controlled latency improvement is claimed. The initial transition reused approximately 74% of input. Absolute fresh-token cost is a more useful speed metric than cache percentage alone. See [HANDOVER.md](HANDOVER.md) for individual observations and accounting methodology.

## Separate follow-up: boilerplate and compact messages

Historical-context accumulation is a different fault domain from the size of the current-turn snapshot. The remaining tail still costs roughly 1,200 fresh tokens per warm request. Prior Forge work is a useful design reference: [Discord inbound compact V2](https://github.com/Animeleague/openclaw/blob/68a80cea08530419faf5fbb9120919b949bfa800/forge-patches/discord-inbound-compact/Patch-ForgeDiscordInboundCompactV2-CORRECTED.ps1) replaced verbose ordinary guild/DM envelopes with compact metadata and preserved stock JSON for unknown/special fields. It also retained V1 trusted-metadata compaction and channel-topic suppression.

A future change should distinguish stable instructions from truly volatile fields, compact ordinary metadata without losing sender, time, channel, mention, reply or trust semantics, and retain bounded recent room history. Do not run the historical compiled patch against a different build. Re-test raw input, fresh/cache tokens, actual recall, owner/non-owner transitions and response time. Keep the five-message lookup until the next candidate is evaluated; test ten separately. This optimisation is deliberately not included in v0.1.

## Compatibility and recovery

The original package passed four unit tests and demonstrated the above behaviour in live traffic. The renamed package passed those same four tests locally; its new identity has not been installed live. This is not a universal provider plugin, fully accepted production release or upstream-ready fix. The implementation deliberately accepts only the tested `local/gemma` reasoning-enabled route at `http://127.0.0.1:1234/v1` using `openai-completions`. Other providers, signed/stateful replay, mixed deployments and later versions require separate validation. Longer traffic, owner/non-owner transitions, idle behaviour and rollback remain unverified.

Run `node --test test.mjs` in this directory. Back up and verify the target profile config before installing. Never install this derivative alongside the original plugin claiming the same provider. **Do not rely on `--no-enable`: the original install automatically activated despite that flag.** Treat linking as a live change unless explicit disablement is verified. Do not reset the conversation. See the handover for recovery details.

The [original recovery commit](https://github.com/Animeleague/openclaw/commit/94a3c0b6979d95329fb9e24aa2bfe38233b766f0) is preserved unchanged. This naming-only derivative does not modify any running installation.
