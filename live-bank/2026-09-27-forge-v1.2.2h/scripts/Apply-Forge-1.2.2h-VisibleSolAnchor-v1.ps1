param(
    [ValidateSet("preflight","apply")]
    [string]$Action = "preflight"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Count-Literal([string]$Text, [string]$Needle) {
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count = 0
    $offset = 0
    while ($true) {
        $i = $Text.IndexOf($Needle, $offset, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $count++
        $offset = $i + $Needle.Length
    }
    return $count
}

function Wait-GatewayHealthy([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        & openclaw gateway status --deep --require-rpc | Out-Host
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

$ExpectedProviderHash = "9f7eb3c6bdbdaba427858b94f7c4e7e57308a1bbf1ad92451aea83f70855467c"
$MarkerG  = "FORGE_SOL_FRESH_CACHE_ANCHOR_V122G"
$MarkerG2 = "FORGE_SOL_CACHE_ANCHOR_COMPLETION_FIX_V122G2"
$MarkerH  = "FORGE_SOL_VISIBLE_FIRST_TURN_ANCHOR_V122H"
$MarkerF  = "FORGE_SOL_ACTUAL_USAGE_SUM_V122F"
$MarkerE  = "FORGE_NATIVE_DELTA_PERSISTED_LEDGER_V122E"

$Dist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$RunAttempt = Join-Path $Dist "run-attempt-FUyOjGCV.js"
$Provider = Join-Path $Dist "provider-capabilities-CDnHbmUZ.js"

foreach ($p in @($RunAttempt, $Provider)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "Required live file missing: $p"
    }
}

$LiveHash = Sha256 $RunAttempt
$ProviderHash = Sha256 $Provider
$LiveText = [IO.File]::ReadAllText($RunAttempt)

Write-Host ""
Write-Host "=== FORGE 1.2.2h - SOL VISIBLE FIRST-TURN CACHE ANCHOR ===" -ForegroundColor Cyan
Write-Host "Action:       $Action"
Write-Host "Live SHA:     $LiveHash"
Write-Host "Provider SHA: $ProviderHash"
Write-Host ""

if ($ProviderHash -ne $ExpectedProviderHash) {
    throw "Provider SHA mismatch. Nothing changed."
}

& node --check $RunAttempt
if ($LASTEXITCODE -ne 0) {
    throw "Live run-attempt fails node --check. Nothing changed."
}

foreach ($required in @(
    $MarkerG,
    $MarkerF,
    $MarkerE,
    "forgeSolCacheAnchorStateV122G",
    "forge.sol-cache-anchor.v122g",
    "sol-cache-anchor-v1.json",
    "forge Sol native cache anchor starting",
    "await waitForActiveNativeTurnCompletion();",
    "forgeRoomContextTxnV122",
    "forge 1.2.2a room dirty-turn placement",
    "forge transient tool transaction committed clean visible history on same native thread",
    "forgePostTurnActualModelInputTokensV122C >= forgePostTurnHardcapTokensV121",
    '"thread/rollback"',
    '"thread/inject_items"'
)) {
    if ((Count-Literal $LiveText $required) -lt 1) {
        throw "Required current invariant missing: $required"
    }
}

if ((Count-Literal $LiveText $MarkerG) -ne 1) {
    throw "Expected 1.2.2g marker exactly once."
}
if ((Count-Literal $LiveText $MarkerF) -ne 1) {
    throw "Expected 1.2.2f marker exactly once."
}
if ((Count-Literal $LiveText $MarkerE) -ne 1) {
    throw "Expected 1.2.2e marker exactly once."
}
if ((Count-Literal $LiveText '"thread/inject_items"') -ne 3) {
    throw "Expected exactly three native thread/inject_items sites."
}
if ((Count-Literal $LiveText 'forgePostTurnActualModelInputTokensV122C >= forgePostTurnHardcapTokensV121') -ne 1) {
    throw "Expected actual-input rollover comparator exactly once."
}
if ($LiveText.Contains($MarkerH)) {
    throw "1.2.2h marker already live. Stop and reassess."
}

# Accept the first broken 1.2.2g or its g2 notification hotfix, but nothing
# outside that structurally verified family.
$G2Count = Count-Literal $LiveText $MarkerG2
if ($G2Count -notin @(0,2)) {
    throw "Unexpected 1.2.2g2 marker count $G2Count. Nothing changed."
}

$Rollover = (& openclaw config get plugins.entries.forge-discord-monitor.config.continuity.solRolloverTokens --json | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Rollover -ne "80000") {
    throw "Expected Sol rollover config 80000; got '$Rollover'. Nothing changed."
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StageDir = "$env:USERPROFILE\Desktop\forge-v122h-visible-sol-anchor-$Stamp"
$BackupDir = "$env:USERPROFILE\Desktop\forge-pre-v122h-visible-sol-anchor-$Stamp"
$Candidate = Join-Path $StageDir "run-attempt-FUyOjGCV.v122h.js"
$PatchJs = Join-Path $StageDir "build-v122h.cjs"
$PreflightState = "$env:USERPROFILE\Downloads\Apply-Forge-1.2.2h-VisibleSolAnchor.preflight.json"

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
[IO.File]::Copy($RunAttempt, $Candidate, $true)

$NodePatch = @'
const fs = require("fs");

const file = process.argv[2];
if (!file) throw new Error("candidate path missing");

let text = fs.readFileSync(file, "utf8");

const H = "FORGE_SOL_VISIBLE_FIRST_TURN_ANCHOR_V122H";

function count(h, n) {
  return h.split(n).length - 1;
}
function replaceOnce(oldText, newText, label) {
  const n = count(text, oldText);
  if (n !== 1) throw new Error(`${label}: expected one anchor, found ${n}`);
  text = text.replace(oldText, newText);
}
function replaceRegexOnce(re, replacement, label) {
  const matches = text.match(new RegExp(re.source, re.flags.includes("g") ? re.flags : re.flags + "g")) ?? [];
  if (matches.length !== 1) throw new Error(`${label}: expected one match, found ${matches.length}`);
  text = text.replace(re, replacement);
}

if (text.includes(H)) throw new Error("1.2.2h marker already present");

/*
 * 1. Retire 1.2.2g's nested synthetic turn. Keep its persisted thread-ID
 *    ledger and loader because 1.2.2h reuses them.
 */
replaceOnce(
  'if (!forgeSolCacheAnchorStateV122G.threads.has(thread.threadId)) {',
  'if (false && !forgeSolCacheAnchorStateV122G.threads.has(thread.threadId)) { // retired nested anchor by ' + H,
  "retire nested 1.2.2g anchor"
);

/*
 * 2. Immediately before the ordinary real-turn path, decide whether this
 *    native Sol thread still needs its first genuine model-visible anchor.
 */
const realTurnAnchor = '\ttry {\n\t\tcodexModelCallDiagnostics.emitStarted();';
replaceOnce(
  realTurnAnchor,
  [
    '\tconst forgeSolVisibleAnchorCandidateV122H =',
    '\t\t(params.modelId ?? "").trim().toLowerCase().split("/").at(-1) === "gpt-5.6-sol" &&',
    '\t\tforgeSolCacheAnchorStateV122G.loaded === true &&',
    '\t\t!forgeSolCacheAnchorStateV122G.threads.has(thread.threadId);',
    '',
    '\tif (forgeSolVisibleAnchorCandidateV122H) {',
    '\t\tembeddedAgentLog.info("forge Sol visible cache-anchor candidate armed", {',
    '\t\t\trunId: params.runId,',
    '\t\t\tthreadId: thread.threadId',
    '\t\t});',
    '\t}',
    '',
    realTurnAnchor
  ].join("\n"),
  "real visible anchor candidate seam"
);

/*
 * 3. On the candidate turn only, omit latest-10 room history from the model
 *    input. The actual user request remains unchanged and gets a normal reply.
 */
replaceRegexOnce(
  /if \(forgeRoomContextTxnV122\?\.roomContextText\) \{\s*const forgeInputItemsV122 = Array\.isArray\(turnStartParams\.input\)/,
  (m) => m.replace(
    'if (forgeRoomContextTxnV122?.roomContextText) {',
    'if (!forgeSolVisibleAnchorCandidateV122H && forgeRoomContextTxnV122?.roomContextText) {'
  ),
  "room-context placement gate"
);

/*
 * 4. Do not arm the room rollback transaction for that candidate turn.
 *    Tool-bearing turns can still arm the existing tool transaction normally.
 */
replaceOnce(
  'if (!forgeSolCacheAnchorModeV122G && forgeRoomContextTxnV122?.roomContextText) {',
  'if (!forgeSolCacheAnchorModeV122G && !forgeSolVisibleAnchorCandidateV122H && forgeRoomContextTxnV122?.roomContextText) {',
  "room transaction arm gate"
);

/*
 * 5. A successful ordinary non-tool/non-NO_REPLY turn is now a genuine
 *    retained model request endpoint. Persist that native thread ID before
 *    entering the existing transaction finalizer.
 */
const successAnchor =
  'shouldDelayNativeHookRelayUnregister = completedTurnStatus === "completed" && !effectiveTimedOut && !runAbortController.signal.aborted && !finalAborted && !finalPromptError;';

replaceOnce(
  successAnchor,
  [
    successAnchor,
    '',
    'if (forgeSolVisibleAnchorCandidateV122H) {',
    '\t\t\tconst forgeSolVisibleAnchorReplyV122H = Array.isArray(result.assistantTexts)',
    '\t\t\t\t? result.assistantTexts',
    '\t\t\t\t\t.filter((value) => typeof value === "string")',
    '\t\t\t\t\t.map((value) => value.trim())',
    '\t\t\t\t\t.filter(Boolean)',
    '\t\t\t\t\t.join("\\n")',
    '\t\t\t\t: "";',
    '',
    '\t\t\tconst forgeSolVisibleAnchorEligibleV122H =',
    '\t\t\t\tshouldDelayNativeHookRelayUnregister &&',
    '\t\t\t\t!forgeTransientToolTurnV3 &&',
    '\t\t\t\tforgeSolVisibleAnchorReplyV122H.length > 0 &&',
    '\t\t\t\tforgeSolVisibleAnchorReplyV122H !== "NO_REPLY";',
    '',
    '\t\t\tif (forgeSolVisibleAnchorEligibleV122H) {',
    '\t\t\t\tconst forgeSolCacheAnchorNextThreadsV122H = new Map(',
    '\t\t\t\t\tforgeSolCacheAnchorStateV122G.threads',
    '\t\t\t\t);',
    '\t\t\t\tforgeSolCacheAnchorNextThreadsV122H.delete(thread.threadId);',
    '\t\t\t\tforgeSolCacheAnchorNextThreadsV122H.set(thread.threadId, Date.now());',
    '\t\t\t\twhile (forgeSolCacheAnchorNextThreadsV122H.size > 128) {',
    '\t\t\t\t\tconst forgeSolCacheAnchorOldestThreadV122H =',
    '\t\t\t\t\t\tforgeSolCacheAnchorNextThreadsV122H.keys().next().value;',
    '\t\t\t\t\tif (forgeSolCacheAnchorOldestThreadV122H === void 0) break;',
    '\t\t\t\t\tforgeSolCacheAnchorNextThreadsV122H.delete(forgeSolCacheAnchorOldestThreadV122H);',
    '\t\t\t\t}',
    '',
    '\t\t\t\tconst forgeSolCacheAnchorLedgerV122H = {',
    '\t\t\t\t\tschemaVersion: 1,',
    '\t\t\t\t\tthreads: [...forgeSolCacheAnchorNextThreadsV122H.entries()].map(',
    '\t\t\t\t\t\t([threadId, anchoredAt]) => ({ threadId, anchoredAt })',
    '\t\t\t\t\t)',
    '\t\t\t\t};',
    '',
    '\t\t\t\tawait forgeSolCacheAnchorStateV122G.fs.mkdir(',
    '\t\t\t\t\tforgeSolCacheAnchorStateV122G.dir,',
    '\t\t\t\t\t{ recursive: true }',
    '\t\t\t\t);',
    '\t\t\t\tconst forgeSolCacheAnchorTmpV122H =',
    '\t\t\t\t\tforgeSolCacheAnchorStateV122G.path + ".tmp";',
    '\t\t\t\tawait forgeSolCacheAnchorStateV122G.fs.writeFile(',
    '\t\t\t\t\tforgeSolCacheAnchorTmpV122H,',
    '\t\t\t\t\tJSON.stringify(forgeSolCacheAnchorLedgerV122H, null, 2),',
    '\t\t\t\t\t"utf8"',
    '\t\t\t\t);',
    '\t\t\t\tawait forgeSolCacheAnchorStateV122G.fs.rename(',
    '\t\t\t\t\tforgeSolCacheAnchorTmpV122H,',
    '\t\t\t\t\tforgeSolCacheAnchorStateV122G.path',
    '\t\t\t\t);',
    '\t\t\t\tforgeSolCacheAnchorStateV122G.threads = forgeSolCacheAnchorNextThreadsV122H;',
    '',
    '\t\t\t\tembeddedAgentLog.info("forge Sol visible cache anchor retained", {',
    '\t\t\t\t\trunId: params.runId,',
    '\t\t\t\t\tthreadId: thread.threadId,',
    '\t\t\t\t\tturnId: activeTurnId,',
    '\t\t\t\t\treplyChars: forgeSolVisibleAnchorReplyV122H.length,',
    '\t\t\t\t\tledgerPath: forgeSolCacheAnchorStateV122G.path',
    '\t\t\t\t});',
    '\t\t\t} else {',
    '\t\t\t\tembeddedAgentLog.info("forge Sol visible cache-anchor candidate not retained; will retry", {',
    '\t\t\t\t\trunId: params.runId,',
    '\t\t\t\t\tthreadId: thread.threadId,',
    '\t\t\t\t\tturnId: activeTurnId,',
    '\t\t\t\t\thadTransactionalToolOrDirtyTurn: Boolean(forgeTransientToolTurnV3),',
    '\t\t\t\t\treplyText: forgeSolVisibleAnchorReplyV122H === "NO_REPLY" ? "NO_REPLY" : "other",',
    '\t\t\t\t\tcompletedTurnStatus',
    '\t\t\t\t});',
    '\t\t\t}',
    '\t\t}'
  ].join("\n"),
  "successful visible anchor persistence seam"
);

/* Hard invariants */
for (const required of [
  H,
  "forgeSolVisibleAnchorCandidateV122H",
  "forge Sol visible cache-anchor candidate armed",
  "forge Sol visible cache anchor retained",
  "forge Sol visible cache-anchor candidate not retained; will retry",
  "sol-cache-anchor-v1.json",
  "FORGE_SOL_ACTUAL_USAGE_SUM_V122F",
  "FORGE_NATIVE_DELTA_PERSISTED_LEDGER_V122E",
  "FORGE_CODEX_ROOM_DIRTY_TRANSACTION_V122A",
  "forgePostTurnActualModelInputTokensV122C >= forgePostTurnHardcapTokensV121"
]) {
  if (!text.includes(required)) throw new Error("candidate lost required invariant: " + required);
}

if (count(text, H) !== 1) throw new Error("1.2.2h marker count must be exactly one");
if (count(text, '"thread/inject_items"') !== 3) throw new Error("native injection count changed");
if (count(text, "FORGE_SOL_ACTUAL_USAGE_SUM_V122F") !== 1) throw new Error("1.2.2f marker count changed");
if (count(text, "FORGE_NATIVE_DELTA_PERSISTED_LEDGER_V122E") !== 1) throw new Error("1.2.2e marker count changed");
if (count(text, "forgePostTurnActualModelInputTokensV122C >= forgePostTurnHardcapTokensV121") !== 1) {
  throw new Error("actual-input rollover comparator changed");
}
if (count(text, 'if (false && !forgeSolCacheAnchorStateV122G.threads.has(thread.threadId)) {') !== 1) {
  throw new Error("nested 1.2.2g anchor was not retired exactly once");
}
if (count(text, '!forgeSolVisibleAnchorCandidateV122H && forgeRoomContextTxnV122?.roomContextText') < 2) {
  throw new Error("visible anchor does not gate both room placement and room transaction arm");
}

fs.writeFileSync(file, text, "utf8");
'@

[IO.File]::WriteAllText($PatchJs, $NodePatch, [Text.UTF8Encoding]::new($false))

& node $PatchJs $Candidate
if ($LASTEXITCODE -ne 0) {
    throw "1.2.2h candidate transform failed. Nothing changed."
}

& node --check $Candidate
if ($LASTEXITCODE -ne 0) {
    throw "1.2.2h candidate failed node --check. Nothing changed."
}

$CandidateText = [IO.File]::ReadAllText($Candidate)
$CandidateHash = Sha256 $Candidate

if ((Count-Literal $CandidateText $MarkerH) -ne 1) {
    throw "Candidate 1.2.2h marker count is not exactly one."
}
if ((Count-Literal $CandidateText $MarkerF) -ne 1) {
    throw "Candidate changed 1.2.2f marker count."
}
if ((Count-Literal $CandidateText $MarkerE) -ne 1) {
    throw "Candidate changed 1.2.2e marker count."
}
if ((Count-Literal $CandidateText '"thread/inject_items"') -ne 3) {
    throw "Candidate changed native injection-site count."
}
if ((Count-Literal $CandidateText 'forgePostTurnActualModelInputTokensV122C >= forgePostTurnHardcapTokensV121') -ne 1) {
    throw "Candidate changed actual-input rollover comparator."
}
if ((Count-Literal $CandidateText 'if (false && !forgeSolCacheAnchorStateV122G.threads.has(thread.threadId)) {') -ne 1) {
    throw "Candidate did not retire nested 1.2.2g anchor exactly once."
}
if ((Count-Literal $CandidateText 'forge Sol visible cache anchor retained') -ne 1) {
    throw "Candidate visible-anchor retention log missing or duplicated."
}

Write-Host "=== PRE-MUTATION RESULT ===" -ForegroundColor Green
Write-Host "Current live SHA:       $LiveHash"
Write-Host "1.2.2h candidate SHA:   $CandidateHash"
Write-Host "Provider SHA:           $ProviderHash"
Write-Host "Sol rollover config:    80000"
Write-Host "1.2.2e ledger:          preserved"
Write-Host "1.2.2f accounting:      preserved"
Write-Host "1.2.2g thread ledger:   reused"
Write-Host "Nested hidden anchor:   retired"
Write-Host "Native injections:      exactly 3"
Write-Host "Candidate node check:   PASS"
Write-Host ""
Write-Host "1.2.2h semantics:"
Write-Host "  - Sol only"
Write-Host "  - unanchored Sol thread -> next ordinary clean visible turn is anchor candidate"
Write-Host "  - candidate turn omits prior-10 room snapshot only"
Write-Host "  - actual user request and normal Forge reply remain unchanged"
Write-Host "  - clean successful reply -> retained + thread ID banked"
Write-Host "  - tool / error / NO_REPLY -> not banked; next clean turn retries"
Write-Host "  - after bank -> normal prior-10 transient rollback/reinject resumes"
Write-Host "  - Luna unchanged"
Write-Host ""

# Bind apply to this exact preflighted live image.
$State = @{
    liveHash = $LiveHash
    candidateHash = $CandidateHash
    providerHash = $ProviderHash
    createdAt = (Get-Date).ToString("o")
}
$State | ConvertTo-Json | Set-Content -LiteralPath $PreflightState -Encoding UTF8

if ($Action -eq "preflight") {
    Write-Host "PASS - 1.2.2h PREFLIGHT ONLY. NOTHING LIVE CHANGED. NO RESTART." -ForegroundColor Green
    Write-Host ""
    Write-Host "Apply with ONE gateway restart:"
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Action apply"
    return
}

if (-not (Test-Path -LiteralPath $PreflightState -PathType Leaf)) {
    throw "Preflight state file missing. Run -Action preflight first."
}
$Saved = Get-Content -LiteralPath $PreflightState -Raw | ConvertFrom-Json

if ([string]$Saved.liveHash -ne $LiveHash) {
    throw "Apply live SHA differs from preflight SHA. Nothing changed."
}
if ([string]$Saved.candidateHash -ne $CandidateHash) {
    throw "Apply candidate SHA differs from preflight candidate. Nothing changed."
}
if ([string]$Saved.providerHash -ne $ProviderHash) {
    throw "Provider SHA differs from preflight. Nothing changed."
}

# Exact recheck immediately before mutation.
if ((Sha256 $RunAttempt) -ne $LiveHash) {
    throw "Live Codex changed during staging. Nothing applied."
}
if ((Sha256 $Provider) -ne $ProviderHash) {
    throw "Provider changed during staging. Nothing applied."
}

$BackupRun = Join-Path $BackupDir "run-attempt-FUyOjGCV.js"
[IO.File]::Copy($RunAttempt, $BackupRun, $true)
if ((Sha256 $BackupRun) -ne $LiveHash) {
    throw "Rollback snapshot SHA mismatch. Nothing applied."
}

$RollbackPath = Join-Path $BackupDir "ROLLBACK.ps1"
$Rollback = @"
`$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Sha256([string]`$Path) {
    return (Get-FileHash -LiteralPath `$Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
`$RunAttempt = "$RunAttempt"
`$BackupRun = "$BackupRun"
`$Expected = "$LiveHash"
if ((Sha256 `$BackupRun) -ne `$Expected) { throw "Rollback source SHA mismatch." }
[IO.File]::Copy(`$BackupRun, `$RunAttempt, `$true)
& node --check `$RunAttempt
if (`$LASTEXITCODE -ne 0) { throw "Rollback source fails node --check." }
if ((Sha256 `$RunAttempt) -ne `$Expected) { throw "Rollback copy SHA mismatch." }
& openclaw gateway restart
if (`$LASTEXITCODE -ne 0) { throw "Gateway restart failed during rollback." }
Write-Host "ROLLBACK PASS - exact pre-1.2.2h bytes restored." -ForegroundColor Green
"@
[IO.File]::WriteAllText($RollbackPath, $Rollback, [Text.UTF8Encoding]::new($false))

[IO.File]::Copy($Candidate, $RunAttempt, $true)

if ((Sha256 $RunAttempt) -ne $CandidateHash) {
    [IO.File]::Copy($BackupRun, $RunAttempt, $true)
    throw "Live copy SHA mismatch. Previous bytes restored; gateway not restarted."
}

& node --check $RunAttempt
if ($LASTEXITCODE -ne 0) {
    [IO.File]::Copy($BackupRun, $RunAttempt, $true)
    throw "Live candidate failed node --check. Previous bytes restored; gateway not restarted."
}

# ONE restart on the successful path.
& openclaw gateway restart
if ($LASTEXITCODE -ne 0) {
    throw "Gateway restart command failed after 1.2.2h copy. Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
}

if (-not (Wait-GatewayHealthy 120)) {
    throw "1.2.2h copied but gateway failed deep health. Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
}

if ((Sha256 $RunAttempt) -ne $CandidateHash) {
    throw "Live run-attempt changed after restart."
}

Write-Host ""
Write-Host "PASS - FORGE 1.2.2h VISIBLE SOL CACHE ANCHOR IS LIVE." -ForegroundColor Green
Write-Host "Live SHA: $CandidateHash"
Write-Host "Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
Write-Host ""
Write-Host "NEXT:"
Write-Host "  1. In your DM to Forge, send a simple normal message such as: you up?"
Write-Host "  2. It should reply normally. That visible clean turn becomes the anchor."
Write-Host "  3. Console should show: forge Sol visible cache anchor retained"
Write-Host "  4. Send one second normal Sol message and check cached tokens."
