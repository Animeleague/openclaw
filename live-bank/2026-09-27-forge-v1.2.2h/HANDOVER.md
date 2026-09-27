# Forge 1.2.2h handover

## Status

**ACCEPTED AND BANKED**

Forge 1.2.2h fixes the Sol prompt-cache regression while preserving the transient room-context architecture and healthy token growth.

## Root cause

The broken Sol generation had no surviving genuine model-request boundary after its stable prefix. Normal room-context turns were rolled back and replaced by synthetic clean history, causing cache lookup to fall back to the small stable prefix (8,448).

A genuine retained native model turn restores the large cache anchor.

## Final implementation

1. Keep the existing bounded canonical/native continuity.
2. On a Sol native thread without a banked anchor, the next ordinary clean visible Sol turn becomes the anchor candidate.
3. That candidate omits the disposable prior-room snapshot for that one turn.
4. A successful ordinary visible non-tool reply is retained and the thread ID is recorded in sol-cache-anchor-v1.json.
5. Tool/error/NO_REPLY candidates are not banked and retry later.
6. After anchoring, normal room turns return to:
   - bounded latest room context + current request
   - model call
   - rollback dirty turn
   - reinject clean current user + assistant pair
7. Luna remains untouched.

The earlier nested hidden-anchor experiment is retired in the live bundle and must not be re-enabled.

## Proven cache behaviour

Healthy post-fix cache settled at:

- 56,832 cached tokens initially
- then 57,088 cached tokens as a newer genuine retained clean boundary became available

Accepted post-fix model inputs:

57,071 -> 57,715 -> 57,783 -> 57,286 -> 57,517 -> 57,664 -> 57,810 -> 58,201

After a successful Sol -> Luna -> Sol continuity test:

58,621 -> 58,699

The Sol cache remained 57,088 on both post-switch calls.

Positive deltas after the expected first transition:

+68, +231, +147, +146, +391, +420, +78

There were **zero 1k+ jumps** in the accepted post-fix sequence, including after the model switch.

## Public-room acceptance

A normal public-channel turn stayed fully cached.

A follow-up room-context test successfully supplied a preceding public-room value to Sol, Sol answered correctly, the dirty turn rolled back, and the clean current user/assistant pair was reinjected.

Switching back to DM remained fully cached.

## Rollover acceptance

Configured threshold remains 80000.

Native physical footprint may exceed 80k without rollover while actual model input is below 80k. This is expected and proves the earlier premature-roll accounting bug remains fixed.

## Do not regress

- Do not restore full-history <conversation_context>.
- Do not increase the bounded room-context window as part of this work.
- Do not add a fourth 	hread/inject_items site.
- Do not change Luna as part of this bank.
- Do not remove persisted native-delta dedupe state.
- Do not switch rollover back to native-footprint accounting.
- Do not re-enable the retired nested hidden anchor.
- Do not treat synthetic clean reinjection as a substitute for a genuine model-request cache anchor.

## Exact identities

- Live Codex SHA: $RunHash
- Provider SHA: $ProviderHash
- Adapter SHA: $AdapterHash
- Sol rollover: 80000
- Native injections: 3
- Base main SHA at bank time: $BaseSha

## Next work

1. Leave the accepted Sol path alone.
2. Allow the next natural actual-input rollover to test 1.2.2h cold-start behaviour on a naturally fresh Sol generation.
3. Remove observation diagnostics only as a separate tested change.
4. Luna is already healthy; do not add the anchor mechanism there unless a demonstrated need appears.