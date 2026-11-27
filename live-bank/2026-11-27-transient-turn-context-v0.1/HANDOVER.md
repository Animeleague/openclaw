# Transient Turn Context v0.1 checkpoint - 2026-11-27

Status: live-demonstrated narrow repair; generic naming derivative, not full performance acceptance or general provider release. The original runtime identity remains installed and its immutable recovery commit is 94a3c0b6979d95329fb9e24aa2bfe38233b766f0. No core or Forge deployment changes. The renamed package has passed four local Node tests but has not been live-installed.

## Scope and mechanism
OpenClaw 2026.11.10 (6ea542f), custom local/gemma reasoning-enabled OpenAI Completions route at loopback LM Studio. Provider-owned buildReplayPolicy opts out of append-only runtime context; the native LLM-boundary filter removes historical typed carriers while retaining the current one. No transcript deletion, no replacement context engine, no changes to model, Discord settings, tools, thinking or shared runtime. This package intentionally rejects unsupported provider routes. Do not apply to signed/stateful Codex replay or other providers without separate review.

## Live evidence (UTC)
Source: operator-supplied raw rendered prompts, prediction event JSONL, session snapshots and LM Studio server-log snapshot. No raw prompts, private chat text, credentials, session IDs or host paths are included in this bank.

Four unit tests passed on operator Windows machine. Linked install reported Gateway generation 5. Plugin inspect: loaded, provider local, auto-activated from configured model despite --no-enable; explicitlyEnabled=false. No manual gateway restart or session reset. Same Discord session ID and 32768-token context limit before and after. Older actual user/assistant messages survived. Raw prompt files 1–4 contained 6,7,8,9 runtime-context carriers respectively; raw files 9–12 each contained one. At 00:40 the model received four recent room messages, correctly recalled three numeric test messages posted without addressing the bot, and the subsequent prompt retained only the current context block with three recent messages. History limit remains 5.

| Request start | Input | Fresh eval | Derived cached | Cache % | Total inference s |
|---|---:|---:|---:|---:|---:|
| 00:16:16 | 12645 | 1115 | 11530 | 91.2 | 32.20 |
| 00:17:57 | 13720 | 1075 | 12645 | 92.2 | 29.42 |
| 00:20:18 | 14805 | 1085 | 13720 | 92.7 | 37.58 |
| 00:38:06 | 6381 | 1654 | 4727 | 74.1 | 30.19 |
| 00:38:52 | 6633 | 1138 | 5495 | 82.8 | 27.64 |
| 00:40:46 | 6854 | 1233 | 5621 | 82.0 | 38.99 |
| 00:41:40 | 7013 | 1277 | 5736 | 81.8 | 24.55 |

Cached = model-reported prompt token count minus server prompt-evaluation token count (inferred accounting, not a separate cache-hit counter). Server LCP similarity independently corroborates approximate cache fraction; f_keep measures retention relative to prior slot and is not the same denominator. Input fell 14805 to 6381; observed growth over last 3 post-fix increments was 252,221,159 (mean 211). Pre-fix two comparable growth increments 1075,1085 (mean 1080). Input growth includes changing current snapshot size and is not an exact durable transcript metric. Warm fresh evaluation averaged 1092 before vs 1216 after. Thus warm cache still works but rate/fresh cost regressed; no claim of equivalent cache efficiency or latency improvement. Remaining per-turn boilerplate and generation speed separate fault domains.

## Recovery / safety
Package files here have naming-only changes from the original uploaded v0.1 artifact. Compare installed hashes against the original bank before claiming byte-exact live recovery; direct live file hashes not yet supplied. Use only on the verified exact route and compatible runtime. Back up profile config, verify hashes, and run node --test test.mjs. Do not install alongside the original provider owner. WARNING: --no-enable did not prevent automatic activation. Treat installation as live apply. To stage disabled, author explicit plugin disablement before linking and verify on the actual runtime. No staging-disable canary or rollback has yet been run; do not claim either verified. If reverting, disable the actual installed plugin ID using the correct isolated profile, verify gateway/model route and prompt behaviour, and restore verified pre-install config if necessary. For the renamed package, the ID is transient-turn-context; original ID and recovery procedure remain in the original checkpoint. Never restore another profile's config. Do not delete session. Existing backup's precise filename/hash not independently confirmed.

## Follow-up gates
Before marking full acceptance: owner/non-owner alternation after install, varied room recall including unrelated messages, longer traffic and idle/cache behavior, explicit disable/rollback verification, compare installed file hashes. No broad compatibility claim. Keep v0.1 unchanged; pursue static/dynamic boilerplate separation in a separate candidate. Increase recent history from 5 to 10 only as an isolated test once initial checks are satisfactory. Preserve useful history, current room lookup and reasoning. Target fresh tokens <=300 and durable growth <=200 per routine exchange; 98% warm cache hit target depends on prompt size. Do not treat this bank as a Forge deployment or upstream-ready patch.
