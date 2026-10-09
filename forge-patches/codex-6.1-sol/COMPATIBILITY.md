# GPT-6.1 Sol compatibility notes for OpenClaw 2026.7.1

## Why this exists

OpenClaw 2026.7.1 predates GPT-6.1 Sol and its newer Codex app-server behaviour.
Forge therefore needed a compatibility bridge rather than a normal model selection change.

## Boundary of the work

The 6.1 enablement did not require source changes in Animeleague's Discord gateway,
Sentry, moderation middleware, silence guard, or other Forge plugins.

Changes were limited to the OpenClaw/Codex layer:

- accepted replacements for three compiled OpenClaw runtime files;
- official Codex 0.159.3 runtime;
- explicit GPT-6.1 Sol model registration;
- Windows unelevated sandbox launch;
- preservation of Forge's existing continuity and transient-history semantics.

The later forge-discord-gateway v1.1.14+ work is routing policy only: it decides who gets
the already-working Sol path versus Luna.

## Accepted behavioural contract

- default Forge high-intelligence path resolves to GPT-6.1 Sol;
- ambient Luna remains available as a sidecar;
- exact-turn revert is used instead of legacy rollback semantics;
- native tools remain app-server-owned;
- no fallback during accepted canaries;
- warm Sol turns retain healthy cache reuse;
- transient Discord room snapshots are reverted rather than accumulated durably;
- no cross-turn token staircase was observed after switch.

## Future migration

When upgrading OpenClaw to a release with native GPT-6.1 support:

1. prove the new release natively resolves GPT-6.1 Sol through its bundled/supported Codex runtime;
2. compare new thread/revert and pagination semantics with this checkpoint;
3. reproduce Sol/Luna continuity and transient-context tests;
4. reproduce native-tool and Windows sandbox tests;
5. verify cache stability and actual-input rollover;
6. only then remove obsolete July compatibility shims.

Do not carry the old model-registration shim or pinned Codex runtime forward merely because they
were once necessary. Conversely, do not remove Forge-specific continuity protections until their
replacement behaviour is proven.
