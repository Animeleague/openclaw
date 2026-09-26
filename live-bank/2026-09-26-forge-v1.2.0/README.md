# Forge 1.2.0 live bank

**Bank date:** 26 September 2026  
**Status:** accepted live production state  
**Scope:** Luna native canonical bootstrap

## What 1.2.0 changes

Forge keeps one long-lived OpenClaw canonical conversation while disposable native Codex threads can renew.

In 1.2.0, a genuinely fresh Luna native thread rebuilds recent conversational continuity once from the exact active OpenClaw canonical session file.

The proven path is:

```text
OpenClaw canonical params.sessionFile
        ↓
existing parse / migrate / build context / image sanitization
        ↓
newest bounded user + assistant conversational tail
        ↓
native thread/inject_items
        ↓
fresh Luna native thread
        ↓
ordinary turn/start
        ↓
normal warm resume + cache reuse
```

The bootstrap is deliberately native rather than a projected synthetic prompt. This is important because Forge monitor-driven Luna turns bypass the ordinary prompt-continuity projection path.

## Fresh-thread policy

- Model: `gpt-5.6-luna`
- Trigger: native lifecycle `action === "started"`
- Canon source: exact `params.sessionFile`
- History budget: 120,000 rendered text characters, used as the planning approximation for ~30k conversational tokens
- User and assistant conversational text only
- Lightweight sender/timestamp provenance retained for user messages
- Historical image payloads remain sanitized
- Injection happens before `turn/start`
- Warm/resumed Luna does not repeat the bootstrap

## Existing behaviour preserved

1.1.9 production behaviour remains unless explicitly listed above:

- Sol remains unchanged
- existing Sol ↔ Luna native delta bridge remains
- monitor routing remains
- monitor projection bypass remains
- transient tool cleanup remains
- privacy / DM eligibility remains
- normal warm native thread caching remains

## Live proof

Accepted proof rollout SHA-256:

`38cfa9919d9775ace82695a2e8bb692d5bcb05c37afd80626453cfdefb55227b`

Fresh Luna:

- 56,407 input tokens
- 0 cached tokens, as expected for a new native generation
- roughly 1,051 historical messages available
- conversational history reached back to 22 September

Warm turns after the bootstrap:

| Turn | Input | Cached |
| --- | ---: | ---: |
| 2 | 57,154 | 56,064 |
| 3 | 57,971 | 56,064 |
| 4 | 58,785 | 57,088 |
| 5 | 59,623 | 58,112 |
| 6 | 60,509 | 59,136 |

This demonstrates:

- canonical hydration is genuinely present
- hydration is not repeated on warm turns
- warm prefix caching is about 97-98%
- context grows normally rather than staircasing
- old hydrated history remains usable several turns later
- the thread remains far below the 258,400-token model context window

## Recall / identity canaries

The fresh Luna thread correctly recalled old session details from 22 September, including details belonging to different Discord users rather than treating all historical user messages as Mike.

This was used as a practical provenance check in addition to token/caching evidence.

## Known non-blocking cleanup

A small number of recent cross-model native-delta pairs may still appear alongside the initial canonical bootstrap when exact-pair dedupe misses formatting/provenance differences.

This did not materially affect token growth, caching, or continuity during acceptance testing. It can be tightened later without reopening the architecture.

## Production hashes

See [HASH-MANIFEST.txt](./HASH-MANIFEST.txt).

## Installer

The exact proven installer is banked at:

`scripts/Apply-Forge-LunaNativeCanon30k-Stage1-v5-1.ps1`

Do not substitute earlier V3/V4/V5 experiments.

## Source-of-truth warning

The earlier draft Stage 1 TypeScript branch contains prompt-projection experiments that were superseded by the live-proven native injection solution.

For Forge 1.2.0, the accepted compiled hashes and this banked installer are the production source of truth until the native architecture is reconciled cleanly into TypeScript source.

## Next version

Forge 1.2.1 will add Sol rolling native sessions.

The intended design is:

- do not rotate Sol merely because the gateway restarts
- retain warm Sol/cache normally
- rotate deliberately when the Sol native context reaches the chosen rollover threshold
- start a fresh Sol native generation
- reuse the same canonical native-bootstrap architecture proven here
- prove warm cache reuse and continuity after rollover before banking 1.2.1
