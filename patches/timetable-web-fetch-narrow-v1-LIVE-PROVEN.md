# Timetable Web Fetch Narrow v1 - Live-Proven Bank

Status: LIVE-PROVEN on Forge/OpenClaw OpenAuth/Codex app-server path
Date: 2026-08-24
Branch: `timetable-web-fetch-narrow-v1`
Parent main commit: `e1c2d5beebc6682b291dcb609c9d42c59ccc7511`

## Purpose

Fix Animeleague event `/timetable` lookups where the HTTP response contains both the desktop timetable and a mobile-app block, but Readability selects only the mobile-app text.

This is deliberately narrow. It does not change normal `web_fetch` extraction globally.

## Trigger conditions

The fallback runs only when all of the following are true:

- hostname has exactly three parts
- first hostname part is `spring`, `summer`, `autumn`, or `winter`
- second hostname part ends in `animecon`, for example `londonanimecon`
- top-level domain is `com`
- pathname is exactly `/timetable` or `/timetable/`
- Readability text contains the known mobile-app timetable message

Example matching host: `summer.londonanimecon.com`

If any condition does not match, original Readability output is returned unchanged.

## Behaviour

When the known timetable stub is detected:

1. Reuse the already-fetched HTML body. No second HTTP request is made.
2. Locate the desktop `<main>` block carrying Tailwind `hidden` and `md:block` classes.
3. Remove only the responsive `hidden` token from that isolated in-memory fragment.
4. Pass that fragment through OpenClaw's existing `extractBasicHtmlContent` path.
5. If usable timetable text is recovered, return it with extractor label `raw-html-timetable`.
6. If recovery fails, retain the original Readability result.

No browser escalation, web search, homepage lookup, or alternate page navigation is part of this patch.

## Files banked

- `patches/timetable-web-fetch-narrow-v1.patch` - intended source equivalent against `src/agents/tools/web-fetch.ts`
- `patches/timetable-web-fetch-narrow-v1-LIVE-RUNTIME.ps1` - exact guarded runtime activator used on Forge
- this file - live proof and rollback evidence

## Live runtime tested

OpenClaw remained pinned at `2026.7.1`.

Live bundle:

`C:\Users\PC User\AppData\Roaming\npm\node_modules\openclaw\dist\openclaw-tools-CIBcX9Ku.js`

Known-good bundle SHA256 before patch:

`A2B93887AA43E263B978EDCAD73151092631CEA74E977358F69C600C7B2F390C`

Live-proven patched bundle SHA256:

`8D76EF1E1704FE548A0BA3E03599CB85B108CF2D24E11BA76472F8267A394BAE`

Untouched rollback copy:

`C:\Users\PC User\Desktop\forge-web-fetch-bank-2026-08-24\openclaw-tools-CIBcX9Ku.KNOWN-GOOD.js`

The live activator verifies the known-good hashes before editing, requires exactly one target Readability branch, runs `node --check`, and restores the bank copy automatically if syntax validation fails.

## Dry-run validation

The exact patch was first applied to a temporary copy only.

Results:

- patch target found exactly once - PASS
- `node --check` on patched temporary bundle - PASS
- live bundle SHA unchanged during dry run - PASS
- bank SHA unchanged - PASS
- dry-run patched SHA matched the later live patched SHA - PASS

Dry-run patched SHA256:

`8D76EF1E1704FE548A0BA3E03599CB85B108CF2D24E11BA76472F8267A394BAE`

## Live validation

After Gateway restart, Forge was asked for the first five Saturday Main Stage events at London Anime & Gaming Con.

The direct lookup used:

`https://summer.londonanimecon.com/timetable`

Observed `web_fetch` result:

- status: `200`
- content type: `text/html`
- extractor: `raw-html-timetable`
- raw length: `2524` characters
- wrapped length: `3295` characters
- truncated: `false`
- fetch time: `218 ms`

Forge returned the expected Saturday Main Stage sequence without the mobile-app message, browser fallback, or raw page inspection.

## Token behaviour

The timetable patch itself did not introduce a large model-visible payload.

London timetable test:

- initial tool-turn input: `27,604`
- initial cached input: `9,984`
- post-fetch model input: `27,734`
- post-fetch cached input: `27,392`
- post-fetch uncached input: `342`

Normal Birmingham guest lookup for comparison:

- initial tool-turn input: `28,119`
- initial cached input: `9,984`
- post-fetch model input: `28,274`
- post-fetch cached input: `27,392`
- post-fetch uncached input: `882`

This supports keeping the timetable patch separate from the later tool-hygiene problem.

## Separate issue discovered during testing

Birmingham exposed an event-to-season mapping problem. Forge initially selected the wrong seasonal hostname for the current event, then spent excessive effort trying to repair the answer through additional fetches and raw HTML inspection.

That behaviour is not caused by this timetable extraction patch and must not be folded into this banked change.

One raw troubleshooting result reached roughly `92,598` characters and a later model call reached `45,883` input tokens with `29,440` cached. Treat that as a separate mapping and minimum-sufficient-tool-usage issue.

## Scope guardrails

Do not broaden this banked patch to:

- all webpages
- all Animeleague pages
- `/guests`
- generic Readability behaviour
- `web_search`
- browser
- shell-based webpage debugging
- generic API or embedded-agent paths
- unrelated token or cache fixes

The value of this patch is that it fixes one proven `/timetable` extraction failure while leaving every other `web_fetch` path unchanged.

## Next integration step

Keep this bank untouched. Separately apply the source equivalent to a working integration branch, add focused regression tests, build OpenClaw, and live-prove the rebuilt result on Forge's OpenAuth/Codex app-server path before any merge to `main`.
