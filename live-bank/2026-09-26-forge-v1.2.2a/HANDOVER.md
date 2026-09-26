# Forge 1.2.2a handover - 2026-09-26

## Current accepted state

The live target at handover is:

```
Monitor 1.1.9
+ Step A exact room-context bridge

Codex 1.2.2a
+ disposable room-context dirty turn
+ rollback
+ clean user/assistant reinjection
+ exact Luna NO_REPLY -> no reinjection

Sol rollover = 80,000
Luna rollover = not implemented
Permanent Resident DM routing = not implemented
```

Exact live/runtime hashes:

- pre-1.2.2a Codex 1.2.1 baseline:
  `9afaf1903efe3958940df446db9b0d71b0e01d5b820f869a1197e70f9452da96`
- Step A live monitor `dist/adapter.js`:
  `692f4fe11ea71a477498cbb87c2b4915fa5d46cad524a4e18e4bdc5171555558`
- broken first Step B candidate:
  `3795fe18aae09ffbd7a68fb4a27f0e0cb1e323e4168f889278822fc0818429b7`
- fixed Step B2 live candidate:
  `46abcc30d783be83ad152566ae01fbe0f54918d8e86c48cce9cae32726b963b8`

Installer SHA-256 values from the deployment machine:

- Step A:
  `6f7b9de7e9db6301e97d1f93d76fce78a08cc6aa30e3a07bdaa764a6942331bb`
- Step B2:
  `cee04d2174fe5f967f8566c732ccf74f23445f231fb3e256152891af1afd1917`

The copies committed here are the same scripts, with repository text serialization potentially normalizing the final newline. Treat the deployment-machine hashes above as the authoritative downloaded-script hashes.

## Architecture

Older failed designs attempted to carry recent room chronology through prompt/developer/additionalContext paths and then clean it up. Those approaches allowed room context to persist or otherwise made transaction ownership unclear.

1.2.2a instead uses a dirty native turn:

```
monitor exact last-10
       |
       v
global bridge keyed by runId
       |
       v
ONE disposable native user turn
  [room context + current request]
       |
       v
model response
       |
       v
rollback dirty turn
       |
       +-- real reply --> reinject clean current user + assistant
       |
       +-- exact NO_REPLY --> reinject nothing
```

The bridge is intentionally tiny and inert until Codex consumes it.

## Step A

Step A changed only the live monitor adapter and left:
- monitor version at 1.1.9;
- plugin registry untouched;
- Codex exact 1.2.1 untouched;
- config untouched.

It exposes the monitor-owned room-context diagnostics map through:

`globalThis[Symbol.for("forge.live-room-context.v1")]`

The compiled candidate was proven to differ from exact live 1.1.9 only by that bridge insertion.

Step A was separately live-tested before Step B. Normal Luna and Sol replies were unchanged.

## Step B v1 failure

The first Step B candidate SHA was:

`3795fe18aae09ffbd7a68fb4a27f0e0cb1e323e4168f889278822fc0818429b7`

It worked through model generation, including exact `NO_REPLY`, but the later finalizer threw:

`ReferenceError: forgeRoomContextTxnV122 is not defined`

Cause:
- `forgeRoomContextTxnV122` was block-scoped where the dirty turn was armed;
- the later transaction finalizer referenced it outside that lexical scope;
- `node --check` cannot detect an unresolved runtime identifier of this kind.

This caused later Luna turns to reach the model but fail before visible reply delivery.

Step B v1 was rolled back to the exact 1.2.1 Codex SHA while leaving Step A live.

## Step B2 fix

A quick `const -> var` scope workaround was considered and rejected.

The accepted fix carries only the later-needed state on the already-existing transaction carrier:

```js
forgeTransientToolTurnV3 = {
  threadId,
  turnId,
  roomContextV122: true,
  cleanPromptTextV122: forgeRoomContextTxnV122.cleanPromptText
}
```

The finalizer then reads:
- `forgeTransientToolTurnV3.roomContextV122`
- `forgeTransientToolTurnV3.cleanPromptTextV122`

It has zero references to the earlier block-scoped `forgeRoomContextTxnV122`.

The Step B2 preflight:
1. reproduced the exact broken v1 SHA `3795fe18...`;
2. built fixed candidate `46abcc30...`;
3. proved the finalizer had zero `forgeRoomContextTxnV122` references;
4. proved reverting only the three intended state-carrier substitutions recreated the exact broken v1 bytes.

## Luna acceptance evidence

Primary Luna native session:
`01a0df9d-ecad-71e3-a2c3-aa8807274e26`

Rollout:
`rollout-2026-09-26T22-27-49-01a0df9d-ecad-71e3-a2c3-aa8807274e26.jsonl`

Observed behaviour:
- room-context recall succeeded;
- normal reply succeeded;
- exact NO_REPLY produced silence;
- later normal reply succeeded;
- dirty turn was rolled back;
- normal turns reinjected clean current user + assistant only;
- NO_REPLY turn reinjected nothing.

The append-only rollout journal still records that the discarded dirty turn occurred. That is expected. The relevant invariant is the active native thread state after rollback/reinjection.

Representative real Luna model calls:

```
input    cached
55,042       0     initial cold turn
55,140  54,016
55,221  54,016    NO_REPLY test
55,211  54,016    normal reply after NO_REPLY
55,271  54,016
55,340  54,016
55,457  54,016
55,564  54,016
55,702  54,016
56,663  54,016
56,271  54,016    after later model switching
56,456  54,016    after later model switching
```

This is flat enough to reject the previous 1k+ staircase failure mode. Warm cache reuse is approximately 95-98% depending on the turn size, with a stable 54,016-token cached prefix through these tests.

## Sol/Luna switching

Further deliberate model alternation showed the same Luna native session continuing after multiple Sol turns.

Observed sequence included:

```
Sol
Luna
Sol
Luna
Sol
```

Luna remained session:
`01a0df9d-ecad-71e3-a2c3-aa8807274e26`

Therefore the old regression where switching through Sol caused Luna to restart was NOT reproduced.

## Sol anomaly - investigate next

This is separate from the accepted 1.2.2a room transaction.

A Sol native file created after gateway restart:

`01a0dfa5-1d37-7253-8f56-2d226b1930dd`

started with:
- first real turn input: 189,198
- cached: 0
- next real turn input: 190,334
- cached: 189,056

This is far above the configured Sol 80,000 rollover threshold.

The existing 1.2.1 rollover logic then correctly caused a replacement Sol file:

`01a0dfa6-2db1-7603-b444-c793c2128487`

which came in at:
- first real turn input: 56,662
- cached: 8,448
- next real turn input: 57,660
- cached: 56,448

So the second Sol file itself looks healthy and cached. The unresolved question is WHY the post-gateway-restart Sol bootstrap was allowed to hydrate a ~189k native turn before the 80k post-turn rollover logic disposed of it.

Do not mistake this for a Sol->Luna reset. The Luna session survived later Sol traffic.

### Next investigation

Before implementing Luna 200k rollover:
1. trace the fresh-Sol/bootstrap path used immediately after gateway restart;
2. identify why it projected ~189k instead of the intended bounded canonical bootstrap;
3. distinguish native pre-existing thread resume from fresh canonical bootstrap;
4. preserve the existing proven Sol 80k rollover behaviour;
5. retest gateway restart -> first Sol turn -> second Sol turn;
6. only after that proceed to 1.2.2b Luna 200k.

## Do not merge in yet

Permanent Resident DM -> Luna routing exists separately in monitor 1.1.10 work, but was intentionally absent throughout 1.2.2a validation.

Do not combine it with the Sol investigation or 1.2.2b. Keep fault domains separate.

## Rollback principle

If 1.2.2a must be removed:
- restore the exact 1.2.1 Codex baseline SHA above;
- Step A can remain independently because it was proven behaviour-neutral, or restore the exact original 1.1.9 adapter if a complete 1.2.2a removal is desired;
- do not mutate plugin registry merely to roll back Step B2.
