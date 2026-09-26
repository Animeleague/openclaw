# Forge 1.2.1 live bank

**Bank date:** 26 September 2026  
**Status:** accepted live production state  
**Scope:** Sol 80k rolling native sessions with canonical continuity

## What 1.2.1 adds

Forge now deliberately rolls the expensive Sol native thread at a much lower threshold while preserving the long-lived OpenClaw canonical conversation.

Policy:

```text
warm Sol native thread
        ↓
completed-turn native context reaches 80k
        ↓
arm clean rollover
        ↓
next Sol use starts a fresh native generation
        ↓
inject bounded recent canonical conversation natively
        ↓
continue as a normal warm cached Sol thread
```

## Current thresholds

- Sol rollover: **80,000**
- Fresh Sol canonical bootstrap: approximately **30k conversational tokens**
- Luna dedicated token rollover: **not yet present in 1.2.1**
- Model context window observed: **258,400**

The Sol threshold is now read from:

`plugins.entries.forge-discord-monitor.config.continuity.solRolloverTokens`

The Luna sidecar still exits the principal post-turn hardcap path before that Sol check.

## Sol proof

The pre-change Sol thread was about 128.6k input/context tokens.

After 1.2.1 rollover, a genuinely new Sol native generation appeared:

`01a0ded2-4cc3-7e63-88b5-ad5a0759f88b`

Observed calls:

| Turn | Input | Cached | Approx cache reuse |
| --- | ---: | ---: | ---: |
| Fresh | 56,345 | 0 | 0% |
| Warm 1 | 56,453 | 56,192 | 99.5% |
| Warm 2 | 56,530 | 56,320 | 99.6% |

Context growth after the fresh bootstrap was only +108 then +77 input tokens.

There was no repeated ~30k re-bootstrap and no staircase-style growth.

## Continuity proof

Canary created before rollover:

`583914`

The fresh Sol generation correctly recalled `583914`.

That proves the new native generation received bounded recent canonical continuity rather than merely restarting empty.

## Luna regression proof

A fresh Luna generation after 1.2.1 remained healthy:

`01a0ded3-f96b-75a1-9367-48b466d0de9a`

Observed:

- fresh: 55,922 input / 0 cached
- next warm turn: 56,834 input / 55,040 cached
- about 96.8% warm cache reuse
- correctly recalled Sol canary `583914`

So the Sol 80k rolling change did not break Luna bootstrap, cross-model continuity or warm caching.

## Exact production hashes

See [HASH-MANIFEST.txt](./HASH-MANIFEST.txt).

## Installer

The exact proven installer is banked at:

`scripts/Apply-Forge-1.2.1-Sol80kRolling-v1.ps1`

## Next - 1.2.2 tidy-up

1. Restore Sol's transient view of the previous 10 public same-channel Discord messages/turns.
   - transient only
   - no persistence into native history
   - no cache staircase
   - respect existing privacy/routing boundaries

2. Add a distinct Luna cap:
   - `lunaRolloverTokens = 200000`
   - clean Luna sidecar rollover at 200k
   - fresh Luna continues using the already-proven ~30k canonical native bootstrap

Sol and Luna must remain independently configured: 80k for Sol, 200k for Luna.
