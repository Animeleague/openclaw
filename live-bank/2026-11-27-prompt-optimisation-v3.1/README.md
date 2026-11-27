# OpenClaw prompt optimisation V3.1

Status: general architectural proposal with a live-observed proof of concept on one tool-free Discord route using OpenClaw 2026.11.10 and a local Gemma model. The implementation is a version-pinned operator overlay, not a native plugin, core patch or upstream release. General applicability remains to be validated. Base commit of this archive branch: 68a80cea08530419faf5fbb9120919b949bfa800.

## The architectural problem

The model's context window is not a dumping ground for application telemetry. OpenClaw should construct prompts according to the capabilities and informational needs of the actual agent, rather than treating every agent as a general-purpose assistant.

On the tested tool-free route, the model receives extensive instructions about tool execution, shell approvals, gateway maintenance and workspace management despite having no tools. It also receives host, session, filesystem, Node and operating-system metadata irrelevant to ordinary conversation. This imposes unnecessary input cost and cognitive load.

Conversation metadata repeats identifiers and equivalent sender labels. Stable channel policy is mixed with volatile per-turn data, which can undermine prompt caching. Machine identifiers and transport details should remain host-side unless the model genuinely needs them. Preserve meaningful identity distinctions, mentions, chronology, reply semantics and trust boundaries.

## General design principles

- Project context according to effective capabilities, not merely the provider or model name.
- Keep stable instructions stable and cacheable; present volatile facts once at their appropriate boundary.
- Remove redundant metadata at its producer, rather than deleting arbitrary historical text.
- Retain information necessary for correctness, security, tool use, attribution and conversational continuity.
- Apply the same principles to local and remote models, tool-enabled and tool-free agents, with route-specific validation rather than blanket deletion.
- Measure token count, cache behaviour, generation time, recall, identity separation, silence decisions and delivery independently.

## Proof of concept

- Policy hoisting: separate invariant channel instructions from changing per-turn facts.
- V1: compact current-turn metadata while preserving meaningful sender identity and channel context.
- V2: compact historical sender metadata only when identities remain unambiguous.
- V3: retrospective runtime deletion was ineffective; its combined loader retains the working V2 implementation.
- V3.1: compact runtime metadata at its source, preserving relocation boundaries and using a scoped checkpoint discriminator for the transition. The runtime block shrank from 405 to 57 characters (85.9%) on three consecutive actual model inputs. Live diagnostics confirmed builder eligibility and checkpoint recognition.

The experiment uses exact baseline bundle hashes and scoped module-load interception without modifying installed files. A reusable upstream implementation should derive its prompt projection from actual capabilities rather than hardcode the proof-of-concept route. Compatibility outside that route has not been demonstrated.

## Sanitised live observations

| Turn | Input tokens | Generated tokens | First token (s) | Total inference (s) |
| --- | ---: | ---: | ---: | ---: |
| 56 | 13,830 | 269 | 97.04 | 117.94 |
| 57 | 13,898 | 172 | 5.14 | 14.81 |
| 58 | 9,855 | 273 | 40.27 | 55.35 |

Follow-up recall outputs matched the supplied recent-chat facts. The compact runtime block persisted. These are observational timings, not a controlled benchmark; cache hits are inferred from timing, not directly measured. Earlier runaway generations inflated history, and one aged out by turn 58. Do not attribute that large token drop to V3.1. The stable system prompt was unchanged by V3.1. Cold-start stalls and output-reasoning separation are independent concerns.

## Roadmap and recovery

V4: compact timestamp and JSON presentation without sacrificing chronology or provenance.

V5: rationalise the system prompt for tool-free conversational agents, preserving all applicable policy and safety requirements.

Then evaluate the capability-driven architecture across additional providers, models and tool-enabled routes before promoting it into a general OpenClaw implementation.

Exact candidate packages, tests, preflight scripts and hashes are retained separately in private recovery staging. This public record excludes private identifiers, machine paths, policy templates, raw prompts and logs. The original installed policy-hoist template and a fresh exact-live file inventory remain necessary for complete recovery. Do not deploy from this README.

No production merge, upstream PR or change to reasoning behaviour is implied.
