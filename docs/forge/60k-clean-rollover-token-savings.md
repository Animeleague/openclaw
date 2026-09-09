# Forge 60k clean rollover - token savings

Banked production state: 2026-09-09

## What changed

Forge now keeps a warm native Codex thread until it reaches 60,000 native tokens. After the completed turn that crosses the cap, the rollover is armed with `historyCoveredThrough` and a `thread_bootstrap` marker. On the next turn the old native binding is retired and the new thread starts from the compact baseline instead of replaying the durable transcript.

## Proven rollover behaviour

The mechanism was proven at a temporary 45,000-token threshold before moving production to 60,000:

- Old rollout: 47,724 input tokens
- Clean fresh rollout: 14,177 input tokens
- Subsequent fresh baseline: 14,451 input tokens
- Warm cache recovered to 98%+

## Expected usage impact

For an active populated chat, the production change is expected to reduce token usage by roughly 50% overall compared with the prior behaviour.

The context-only component is approximately a 47% reduction in average carried context when comparing a ~14k fresh baseline and 60k ceiling with the previous ~70k average-context regime. Tool-heavy chats can save more effectively because native tool turns now preserve warm cache affinity instead of forcing repeated cold replays.

This is an operational estimate rather than a guarantee for every individual turn. Savings vary with message volume, tool-output size, cache behaviour, and rollover frequency.

## Remaining limitation

Raw native tool output still accumulates in the Codex rollout until rollover. The 60k cap bounds that accumulation, but transient native tool-result removal remains a separate future optimisation.
