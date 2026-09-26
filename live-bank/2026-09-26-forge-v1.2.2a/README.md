# Forge 1.2.2a live bank - 2026-09-26

This bank preserves the accepted Forge 1.2.2a runtime design and deployment path on top of the previously banked 1.2.1 Sol rolling-session baseline.

## Banked live state

- OpenClaw: 2026.7.1 (2d2ddc4)
- Discord monitor package: 1.1.9
- Monitor Step A bridge live adapter SHA-256:
  `692f4fe11ea71a477498cbb87c2b4915fa5d46cad524a4e18e4bdc5171555558`
- Codex Step B2 fixed state-carrier bundle SHA-256:
  `46abcc30d783be83ad152566ae01fbe0f54918d8e86c48cce9cae32726b963b8`
- Sol rollover config: 80000 tokens
- Luna rollover cap: NOT added yet
- Permanent Resident DM routing: NOT added yet

## What 1.2.2a changes

The monitor exposes its exact bounded room-context snapshot by runId through the inert global bridge:

`Symbol.for("forge.live-room-context.v1")`

Codex consumes that exact room context inside one disposable native user turn together with the current request. After the model finishes:

- the dirty turn is rolled back;
- a real reply reinjects only the clean current user message + assistant reply;
- exact Luna `NO_REPLY` reinjects nothing.

The previous-10 room context therefore remains model-visible for the current turn without becoming durable native conversation history.

## Deployment

Apply in two isolated stages:

1. `scripts/Apply-Forge-1.2.2a-StepA-BridgeOnly-v1.ps1`
2. `scripts/Apply-Forge-1.2.2a-StepB2-StateCarrierFix-v1.ps1`

Both scripts default to preflight. Run preflight first.

## Acceptance status

1.2.2a room transaction: ACCEPTED.

Observed:
- room context visible to Luna;
- dirty turn rollback occurs;
- real replies reinject a clean user/assistant pair;
- exact `NO_REPLY` is silent and leaves no clean durable pair;
- later normal Luna replies still work after `NO_REPLY`;
- warm Luna token input stayed roughly flat around 55-56k with ~54k cached;
- repeated Sol/Luna alternation did not reset the Luna native session.

## Do not proceed blindly to 1.2.2b

A separate Sol fresh-bootstrap anomaly was observed after gateway restart: one new Sol native file started at ~189k input despite the 80k rollover ceiling, then correctly rolled to another fresh Sol file around 56.6k.

That anomaly must be understood before adding Luna 200k rolling-session logic.

See `HANDOVER.md` for the full investigation state.
