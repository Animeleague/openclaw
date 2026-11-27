# Ember prompt metadata optimisation V3.1

Status: live-observed prompt reduction; public engineering record, not a complete recovery bank. OpenClaw 2026.11.10, local Gemma, tool-free Discord channel route. Base commit of this archive branch: 68a80cea08530419faf5fbb9120919b949bfa800. This is an isolated operator overlay experiment, not a core patch or an upstream release.

## What is wrong with the existing design?

The model-facing prompt is not an operational telemetry dump. The tested route exposes no tools, yet the model receives extensive instructions about tool execution, shell approvals, gateway maintenance and workspace management. It cannot act on those instructions. It also receives host, session, filesystem, Node and operating-system metadata that is irrelevant to ordinary channel replies. That is needless input cost and unnecessary cognitive load.

Conversation metadata also repeats identifiers and equivalent sender labels, while recurring channel policy is mixed with changing per-turn data. Stable instructions should remain cacheable, and volatile data should be presented once, compactly, at the appropriate boundary. Machine identifiers and transport details belong in host-side state unless the model needs them to perform an available action. Preserve meaningful identity distinctions, mentions, chronology, reply semantics and trust boundaries.

The problem is not that this metadata can never be useful; it is that the prompt is insufficiently adapted to the actual capabilities of this route. A tool-free conversational agent should not pay the input cost of a general-purpose tool-using agent on every exchange. This is an architectural inefficiency, not a claim about the competence or motives of individual maintainers.

## Changes observed

- Hoist invariant channel policy out of per-turn context while retaining changing facts.
- V1: compact current-turn metadata, preserving meaningful sender identity and channel context.
- V2: compact historical sender metadata only when identities remain unambiguous.
- V3: historical runtime deletion experiment was ineffective; its combined loader retains the working V2 implementation.
- V3.1: compact the runtime payload at its producer, retaining relocation boundaries and using a scoped checkpoint discriminator for the transition. The runtime block shrank from 405 to 57 characters (85.9%) on three consecutive actual model inputs. The diagnostic variant confirmed both builder eligibility and compact payload recognition at the checkpoint.

The overlays are scoped to the tested tool-free route, use exact baseline bundle hashes, and intercept module loads without editing installed files. This is deliberately not yet a native plugin or a general upstream solution.

## Sanitised live observations

| Turn | Input tokens | Generated tokens | First token (s) | Total inference (s) |
| --- | ---: | ---: | ---: | ---: |
| 56 | 13,830 | 269 | 97.04 | 117.94 |
| 57 | 13,898 | 172 | 5.14 | 14.81 |
| 58 | 9,855 | 273 | 40.27 | 55.35 |

Follow-up recall outputs matched the supplied recent-chat facts. The compact runtime block persisted. These are observational timings, not a controlled speed benchmark; cache-hit status is inferred from timing, not directly measured. Earlier runaway outputs inflated the history and one aged out by turn 58. Do not attribute that large token drop to V3.1. The stable system prompt was unchanged by V3.1. Cold-start stalls and output-reasoning separation remain separate concerns.

## Recovery status and next steps

Exact original candidate archives, tests, preflight scripts and hashes have been retained separately in private recovery staging. This public record intentionally excludes private fixture identifiers, machine paths, policy templates, raw prompts and logs. The original installed policy-hoist template and a fresh exact-live file inventory are still required for a complete restoration bank. Do not deploy from this README.

V4: compact timestamp and JSON presentation without sacrificing chronology or provenance. V5: rationalise the system prompt for tool-free conversational agents. Measure input size, warm/cold prefill, generation time, recall, identity separation, silence decisions and delivery independently. No changes to the reasoning watchdog or other agents are included. Keep the known-good loader stack intact while developing future variants.

No production merge or upstream PR is implied.
