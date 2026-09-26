# Forge 1.2.x rolling-session roadmap

## 1.2.0 - Luna native canonical bootstrap - BANKED

Status: live-proven 26 September 2026.

Accepted behaviour:

- fresh Luna native generation hydrates once from active OpenClaw canon
- native `thread/inject_items` bootstrap before `turn/start`
- approximately 30k conversational-token planning budget via 120k rendered chars
- historical images sanitized
- sender/timestamp provenance retained
- warm Luna resumes without re-bootstrap
- warm cache reuse proven at roughly 97-98%
- no staircase-style context growth observed
- Sol unchanged

See this bank's README and HASH-MANIFEST for exact production proof.

---

## 1.2.1 - Sol rolling native sessions - NEXT

Goal:

Keep the long-lived OpenClaw logical/canonical conversation while deliberately rotating only the disposable Sol native Codex generation when it becomes large.

### Intended behaviour

Normal gateway restart:

```text
warm Sol native thread
        ↓
resume unchanged
        ↓
keep cache
```

Threshold rollover:

```text
warm Sol native thread
        ↓
projected/native context reaches rollover threshold
        ↓
retire/clear current Sol native binding
        ↓
start fresh Sol native generation
        ↓
hydrate recent canon using 1.2.0 native bootstrap mechanism
        ↓
continue normally with warm cache
```

### Initial target

- proposed Sol rollover threshold: about 80k input/context tokens
- fresh Sol canonical bootstrap: about 30k recent conversational tokens
- actual model context window remains about 258,400 tokens
- threshold is a hygiene/cache/continuity policy, not the model hard limit

### Requirements

1. Gateway restart must not itself rotate a healthy Sol thread.
2. Rollover must occur only from the explicit Sol threshold policy.
3. Use the actual projected/native context metric, not cumulative token usage.
4. Reuse the 1.2.0 canonical reader/sanitizer/native injection approach.
5. Hydrate only the newly started Sol generation.
6. Do not repeat canon bootstrap on warm Sol turns.
7. Preserve Luna sidecar behaviour.
8. Preserve monitor routing, transient cleanup and privacy boundaries.
9. Ensure the old Sol binding is not silently resumed after deliberate rollover.
10. Prove the first post-rollover turn has the bounded canonical history and the following warm turn reuses cache.
11. Keep a guarded rollback path before any live proof.

### Acceptance proof

Before banking 1.2.1:

- capture pre-rollover Sol thread/token state
- trigger rollover at a controlled threshold
- prove a different native Sol thread ID is active
- prove old canonical history is present in the fresh generation
- verify no repeated bootstrap on second turn
- verify warm cache reuse
- verify context grows normally
- verify Luna behaviour is unchanged
- verify exact live hashes and bank them

---

## Later cleanup

Potential follow-up after rolling sessions are proven:

- tighten exact-pair dedupe between canonical bootstrap and cross-model native delta
- reconcile direct-live Forge patches into clean TypeScript source
- remove obsolete Stage 1 prompt-projection experiment branches/code
