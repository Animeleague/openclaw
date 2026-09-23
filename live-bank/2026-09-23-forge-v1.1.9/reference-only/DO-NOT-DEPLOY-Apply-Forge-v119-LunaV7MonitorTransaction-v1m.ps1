param(
    [switch]$PreflightOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Count-Literal([string]$Text, [string]$Needle) {
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count = 0
    $start = 0
    while ($true) {
        $idx = $Text.IndexOf($Needle, $start, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $count++
        $start = $idx + $Needle.Length
    }
    return $count
}

function Replace-Literal-Once(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
) {
    $count = Count-Literal $Text $Old
    if ($count -ne 1) {
        throw "$Label - expected exactly one literal match, found $count."
    }
    return $Text.Replace($Old, $New)
}

function Replace-Regex-Once(
    [string]$Text,
    [string]$Pattern,
    [string]$Replacement,
    [string]$Label
) {
    $rx = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches = $rx.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "$Label - expected exactly one regex match, found $($matches.Count)."
    }
    return $rx.Replace($Text, $Replacement, 1)
}

$RunAttempt = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist\run-attempt-FUyOjGCV.js"

# Exact v1i candidate that Mike applied live.
$ExpectedLiveHash = "87abfb4183bba56ffd9c6f345c405dea9083b5990172d3cbac059827fb5bcded"

$V7Marker = "FORGE_CODEX_ROOM_CONTEXT_TRANSACTIONAL_V7"
$OldCleanupMarker = "FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119I"
$OldStateMarker = "FORGE_CODEX_LUNA_NO_REPLY_ENTRY_STATE_V119I"

$TxnMarker = "FORGE_CODEX_MONITOR_CLEAN_TXN_V119M"
$NoReplyMarker = "FORGE_CODEX_MONITOR_NO_REPLY_FROM_NATIVE_TURN_V119M"
$Final9Marker = "FORGE_CODEX_FINAL9_BOOKKEEPING_ONLY_V119M"

Write-Host ""
Write-Host "=== FORGE 1.1.9 LUNA V7 MONITOR TRANSACTION v1m ===" -ForegroundColor Cyan
Write-Host "One owner: existing V7 rollback/reinject transaction"
Write-Host "Normal Luna reply: rollback dirty latest-10 turn, inject clean user + assistant"
Write-Host "Exact NO_REPLY:   rollback dirty turn, inject nothing"
Write-Host "FINAL9:           bookkeeping only, no semantic rollback"
Write-Host "Sol / sidecars / native delta: untouched"
Write-Host ""

if (-not (Test-Path -LiteralPath $RunAttempt -PathType Leaf)) {
    throw "Active Codex bundle not found: $RunAttempt"
}

$LiveHash = Sha256 $RunAttempt
Write-Host "Live SHA: $LiveHash"

if ($LiveHash -ne $ExpectedLiveHash) {
    throw "Live SHA mismatch. Expected exact v1i $ExpectedLiveHash but found $LiveHash. Nothing modified."
}

$BaseText = [IO.File]::ReadAllText($RunAttempt)

foreach ($required in @(
    $V7Marker,
    $OldCleanupMarker,
    $OldStateMarker,
    'forge room context armed existing clean-turn transaction',
    'forge transient tool transaction committed clean visible history on same native thread',
    'const forgeTransientToolTxnMonitorV1 =',
    '!forgeTransientToolTxnMonitorV1',
    'const forgeTxnAssistantTextV1 =',
    '"thread/rollback"',
    '"thread/inject_items"',
    'await markCodexAppServerBindingCoveredThroughTurn({',
    'const assistantTranscriptOwned = await mirrorTranscriptBestEffort({'
)) {
    if ((Count-Literal $BaseText $required) -lt 1) {
        throw "Required v1i/V7 structure missing: $required"
    }
}

foreach ($forbidden in @(
    $TxnMarker,
    $NoReplyMarker,
    $Final9Marker
)) {
    if ((Count-Literal $BaseText $forbidden) -ne 0) {
        throw "v1m marker already present: $forbidden"
    }
}

$CandidateText = $BaseText

# -------------------------------------------------------------------------
# 1. Replace v1i's disposable-entry carrier with an independent per-run map.
#    Capture exact NO_REPLY exactly where result.assistantTexts is proven in
#    scope. This does not depend on monitor-entry creation timing.
# -------------------------------------------------------------------------

$StatePattern =
    'const forgeLunaMonitorStateV119I\s*=\s*' +
    'globalThis\[Symbol\.for\("forge\.native-thread-rollback\.v1"\)\];\s*' +
    'const forgeLunaMonitorEntryV119I\s*=\s*' +
    'forgeLunaMonitorStateV119I\?\.disposableRuns instanceof Map\s*' +
    '\?\s*forgeLunaMonitorStateV119I\.disposableRuns\.get\(params\.runId\)\s*' +
    ':\s*void 0;\s*' +
    'if \(forgeLunaMonitorEntryV119I\?\.reason === "forge-monitor"\) \{\s*' +
    'forgeLunaMonitorEntryV119I\.exactNoReplyV119I\s*=\s*' +
    'attemptSucceeded &&\s*' +
    'params\.allowEmptyAssistantReplyAsSilent === true &&\s*' +
    'Array\.isArray\(result\.assistantTexts\) &&\s*' +
    'result\.assistantTexts\.length === 1 &&\s*' +
    'result\.assistantTexts\[0\]\?\.trim\(\) === "NO_REPLY";\s*// FORGE_CODEX_LUNA_NO_REPLY_ENTRY_STATE_V119I\s*' +
    '\}\s*' +
    '(?=const assistantTranscriptOwned = await mirrorTranscriptBestEffort\(\{)'

$StateReplacement = @'
const forgeLunaNoReplyStateV119M =
                        globalThis[Symbol.for("forge.luna-monitor-no-reply.v119l")] ??=
                                new Map();
                const forgeLunaExactNoReplyV119M =
                        attemptSucceeded &&
                        params.allowEmptyAssistantReplyAsSilent === true &&
                        Array.isArray(result.assistantTexts) &&
                        result.assistantTexts.length === 1 &&
                        result.assistantTexts[0]?.trim() === "NO_REPLY"; // FORGE_CODEX_LUNA_NO_REPLY_MAP_V119M
                forgeLunaNoReplyStateV119M.set(
                        params.runId,
                        forgeLunaExactNoReplyV119M
                );
'@

$CandidateText = Replace-Regex-Once `
    $CandidateText `
    $StatePattern `
    $StateReplacement `
    "replace v1i disposable-entry NO_REPLY carrier"

# Transcript mirroring is earlier than the V7 transaction in this build.
# Guard it independently by its unique anchor.
$MirrorOld = 'const assistantTranscriptOwned = await mirrorTranscriptBestEffort({'
$MirrorCount = Count-Literal $CandidateText $MirrorOld
Write-Host "Transcript mirror anchors: $MirrorCount"
if ($MirrorCount -ne 1) {
    throw "Expected exactly one transcript mirror anchor, found $MirrorCount."
}

$MirrorNew = @'
const assistantTranscriptOwned = forgeLunaExactNoReplyV119M
                        ? false
                        : await mirrorTranscriptBestEffort({
'@

$CandidateText = Replace-Literal-Once `
    $CandidateText `
    $MirrorOld `
    $MirrorNew `
    "guard transcript mirror for exact NO_REPLY"

# -------------------------------------------------------------------------
# 2. Make the independent NO_REPLY map visible to the existing transaction.
#    No lexical reference to result is needed here.
# -------------------------------------------------------------------------

$TxnFinalizerAnchor = 'if (shouldDelayNativeHookRelayUnregister) try {'

$TxnFinalizerInsert = @'
const forgeLunaNoReplyStateTxnV119M =
                        globalThis[Symbol.for("forge.luna-monitor-no-reply.v119l")];
                if (shouldDelayNativeHookRelayUnregister) try {
'@

$CandidateText = Replace-Literal-Once `
    $CandidateText `
    $TxnFinalizerAnchor `
    $TxnFinalizerInsert `
    "transaction NO_REPLY map lookup insertion"

# -------------------------------------------------------------------------
# 3. Fix the actual root cause:
#    V7 arms forgeTransientToolTurnV3 for room-context turns, but the existing
#    finalizer explicitly excluded forge-monitor. Remove ONLY that exclusion.
# -------------------------------------------------------------------------

$TxnGatePattern =
    'if\s*\(\s*' +
    'forgeTransientToolTurnV3\?\.threadId === thread\.threadId &&\s*' +
    'Boolean\(forgeTransientToolTurnV3\?\.turnId\) &&\s*' +
    '!forgeTransientToolTxnMonitorV1\s*' +
    '\)\s*\{'

$TxnGateReplacement = @'
if (
                                forgeTransientToolTurnV3?.threadId === thread.threadId &&
                                Boolean(forgeTransientToolTurnV3?.turnId)
                        ) { // FORGE_CODEX_MONITOR_CLEAN_TXN_V119M
'@

$CandidateText = Replace-Regex-Once `
    $CandidateText `
    $TxnGatePattern `
    $TxnGateReplacement `
    "enable existing clean transaction for V7 monitor turns"

# -------------------------------------------------------------------------
# 4. Confirm the mapped NO_REPLY decision against native thread/read.
#    Both must agree before clean reinjection is suppressed.
# -------------------------------------------------------------------------

$AssistantExtractPattern =
    'const forgeTxnAssistantTextV1\s*=\s*' +
    'forgeTxnItemTextV1\(forgeTxnAssistantItemV1\);'

$AssistantExtractReplacement = @'
const forgeTxnAssistantTextV1 =
                                        forgeTxnItemTextV1(forgeTxnAssistantItemV1);

                                const forgeTxnMappedNoReplyV119M =
                                        forgeTransientToolTxnMonitorV1 &&
                                        forgeLunaNoReplyStateTxnV119M instanceof Map &&
                                        forgeLunaNoReplyStateTxnV119M.get(params.runId) === true;

                                if (
                                        forgeTxnMappedNoReplyV119M &&
                                        forgeTxnAssistantTextV1?.trim() !== "NO_REPLY"
                                ) {
                                        throw new Error(
                                                "forge monitor NO_REPLY map/native readback mismatch"
                                        );
                                }

                                const forgeTxnMonitorExactNoReplyV119M =
                                        forgeTxnMappedNoReplyV119M &&
                                        forgeTxnAssistantTextV1?.trim() === "NO_REPLY"; // FORGE_CODEX_MONITOR_NO_REPLY_FROM_NATIVE_TURN_V119M
'@

$CandidateText = Replace-Regex-Once `
    $CandidateText `
    $AssistantExtractPattern `
    $AssistantExtractReplacement `
    "map/native exact NO_REPLY agreement"

# -------------------------------------------------------------------------
# 5. Existing transaction always rolls back the dirty turn.
#    Scope ALL edits to the unique V7 transaction block. The bundle contains
#    other thread/inject_items calls which are unrelated and must not move.
# -------------------------------------------------------------------------

$TxnScopeStartNeedle = "// FORGE_CODEX_MONITOR_CLEAN_TXN_V119M"
$TxnScopeEndNeedle = "forgeTransientToolTurnV3 = void 0;"

$TxnScopeStart = $CandidateText.IndexOf(
    $TxnScopeStartNeedle,
    [System.StringComparison]::Ordinal
)
if ($TxnScopeStart -lt 0) {
    throw "v1m transaction scope start marker not found."
}

$TxnScopeEndAnchor = $CandidateText.IndexOf(
    $TxnScopeEndNeedle,
    $TxnScopeStart,
    [System.StringComparison]::Ordinal
)
if ($TxnScopeEndAnchor -lt 0) {
    throw "v1m transaction scope end marker not found."
}

$TxnScopeEnd = $TxnScopeEndAnchor + $TxnScopeEndNeedle.Length
$TxnScope = $CandidateText.Substring(
    $TxnScopeStart,
    $TxnScopeEnd - $TxnScopeStart
)

$ScopedInjectCount = Count-Literal $TxnScope '"thread/inject_items"'
Write-Host "Scoped V7 inject_items refs: $ScopedInjectCount"
if ($ScopedInjectCount -ne 1) {
    throw "Expected exactly 1 thread/inject_items inside V7 transaction scope, found $ScopedInjectCount."
}

$InjectPattern = 'await client\.request\(\s*"thread/inject_items",'
$InjectReplacement = @'
if (!forgeTxnMonitorExactNoReplyV119M) await client.request(
                                        "thread/inject_items",
'@

$TxnScope = Replace-Regex-Once `
    $TxnScope `
    $InjectPattern `
    $InjectReplacement `
    "scoped skip clean reinjection for exact NO_REPLY"

$CommitLogOld = '"forge transient tool transaction committed clean visible history on same native thread",'
$CommitLogNew = @'
forgeTxnMonitorExactNoReplyV119M
                                                ? "forge monitor exact NO_REPLY removed by clean transaction"
                                                : "forge transient tool transaction committed clean visible history on same native thread",
'@

$TxnScope = Replace-Literal-Once `
    $TxnScope `
    $CommitLogOld `
    $CommitLogNew `
    "scoped transaction outcome diagnostic"

$CandidateText =
    $CandidateText.Substring(0, $TxnScopeStart) +
    $TxnScope +
    $CandidateText.Substring($TxnScopeEnd)

# Re-resolve the scope end after replacement, then modify ONLY the first
# binding-coverage call immediately following this transaction finalizer.
$TxnScopeEndAnchor = $CandidateText.IndexOf(
    $TxnScopeEndNeedle,
    $TxnScopeStart,
    [System.StringComparison]::Ordinal
)
$TxnScopeEnd = $TxnScopeEndAnchor + $TxnScopeEndNeedle.Length

$CoverageOld = 'await markCodexAppServerBindingCoveredThroughTurn({'
$CoverageNew = 'if (!forgeTxnMonitorExactNoReplyV119M) await markCodexAppServerBindingCoveredThroughTurn({'

$CoverageIndex = $CandidateText.IndexOf(
    $CoverageOld,
    $TxnScopeEnd,
    [System.StringComparison]::Ordinal
)
if ($CoverageIndex -lt 0) {
    throw "Could not find binding coverage call after V7 transaction."
}
if (($CoverageIndex - $TxnScopeEnd) -gt 2500) {
    throw "Binding coverage call is unexpectedly far from V7 transaction end; refusing broad patch."
}

$CandidateText =
    $CandidateText.Substring(0, $CoverageIndex) +
    $CoverageNew +
    $CandidateText.Substring($CoverageIndex + $CoverageOld.Length)

# -------------------------------------------------------------------------
# 6. FINAL9 no longer owns turn semantics.
#    Keep its preserve/fail-closed bookkeeping, disable its second rollback.
# -------------------------------------------------------------------------

$Final9GatePattern =
    'const forgeLunaMonitorNoReplyV119I\s*=\s*' +
    'shouldDelayNativeHookRelayUnregister &&\s*' +
    'forgeNativeMonitorCleanupEntryV109\?\.exactNoReplyV119I === true;\s*' +
    '// FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119I'

$Final9GateReplacement = @'
const forgeLunaMonitorNoReplyV119M = false; // FORGE_CODEX_FINAL9_BOOKKEEPING_ONLY_V119M
'@

$CandidateText = Replace-Regex-Once `
    $CandidateText `
    $Final9GatePattern `
    $Final9GateReplacement `
    "disable FINAL9 semantic rollback"

$OldNameCount = Count-Literal $CandidateText 'forgeLunaMonitorNoReplyV119I'
if ($OldNameCount -ne 2) {
    throw "Expected exactly 2 remaining v1i FINAL9 boolean references, found $OldNameCount."
}
$CandidateText = $CandidateText.Replace(
    'forgeLunaMonitorNoReplyV119I',
    'forgeLunaMonitorNoReplyV119M'
)

$CandidateText = Replace-Literal-Once `
    $CandidateText `
    '"forge Luna monitor cleanup retained V7 clean replied turn"' `
    '"forge Luna monitor FINAL9 bookkeeping after clean transaction"' `
    "rename FINAL9 diagnostic"


$CandidateText = Replace-Literal-Once `
    $CandidateText `
    'forgeNativeMonitorCleanupStateV109?.disposableRuns?.delete(params.runId);' `
    @'
forgeNativeMonitorCleanupStateV109?.disposableRuns?.delete(params.runId);
                        globalThis[Symbol.for("forge.luna-monitor-no-reply.v119l")]?.delete?.(params.runId);
'@ `
    "cleanup per-run NO_REPLY map"

# -------------------------------------------------------------------------
# 7. Hard invariants.
# -------------------------------------------------------------------------

if ((Count-Literal $CandidateText $V7Marker) -ne 1) {
    throw "V7 room-context marker count changed."
}
if ((Count-Literal $CandidateText $TxnMarker) -ne 1) {
    throw "v1m transaction marker count is not exactly one."
}
if ((Count-Literal $CandidateText $NoReplyMarker) -ne 1) {
    throw "v1m NO_REPLY marker count is not exactly one."
}
if ((Count-Literal $CandidateText 'FORGE_CODEX_LUNA_NO_REPLY_MAP_V119M') -ne 1) {
    throw "v1m NO_REPLY map marker count is not exactly one."
}
if ((Count-Literal $CandidateText $Final9Marker) -ne 1) {
    throw "v1m FINAL9 marker count is not exactly one."
}
if ((Count-Literal $CandidateText $OldCleanupMarker) -ne 0) {
    throw "Old v1i cleanup marker remains."
}
if ((Count-Literal $CandidateText $OldStateMarker) -ne 0) {
    throw "Old v1i result-state marker remains."
}
if ((Count-Literal $CandidateText '!forgeTransientToolTxnMonitorV1') -ne 0) {
    throw "Monitor exclusion still exists in transaction gate."
}
if ((Count-Literal $CandidateText 'result.assistantTexts[0]?.trim() === "NO_REPLY"') -ne 1) {
    throw "Expected exactly one result-based NO_REPLY detector at proven pre-mirror scope."
}
if ((Count-Literal $CandidateText 'forgeTxnAssistantTextV1?.trim() === "NO_REPLY"') -lt 1) {
    throw "Native-turn NO_REPLY confirmation missing."
}
if ((Count-Literal $CandidateText 'forgeLunaNoReplyStateTxnV119M.get(params.runId) === true') -ne 1) {
    throw "Transaction does not consume the per-run NO_REPLY map exactly once."
}
if ((Count-Literal $CandidateText 'const assistantTranscriptOwned = forgeLunaExactNoReplyV119M') -ne 1) {
    throw "Transcript mirror is not guarded by exact NO_REPLY exactly once."
}
if ((Count-Literal $CandidateText 'if (!forgeTxnMonitorExactNoReplyV119M) await client.request(') -ne 1) {
    throw "NO_REPLY inject suppression missing or duplicated."
}
if ((Count-Literal $CandidateText 'forge monitor exact NO_REPLY removed by clean transaction') -ne 1) {
    throw "NO_REPLY transaction success diagnostic missing."
}
if ((Count-Literal $CandidateText 'forge transient tool transaction committed clean visible history on same native thread') -ne 1) {
    throw "Normal clean transaction diagnostic missing."
}
if ((Count-Literal $CandidateText 'if (!forgeTxnMonitorExactNoReplyV119M) await markCodexAppServerBindingCoveredThroughTurn({') -ne 1) {
    throw "NO_REPLY binding-coverage suppression missing."
}
if ((Count-Literal $CandidateText 'const forgeLunaMonitorNoReplyV119M = false;') -ne 1) {
    throw "FINAL9 semantic rollback is not disabled exactly once."
}
if ((Count-Literal $CandidateText 'globalThis[Symbol.for("forge.luna-monitor-no-reply.v119l")]?.delete?.(params.runId);') -ne 1) {
    throw "Per-run NO_REPLY map cleanup missing or duplicated."
}
if ((Count-Literal $CandidateText '"thread/rollback"') -lt 1) {
    throw "Existing native rollback machinery disappeared."
}
if ((Count-Literal $CandidateText '"thread/inject_items"') -lt 1) {
    throw "Existing native inject machinery disappeared."
}
if ((Count-Literal $CandidateText 'forge room context armed existing clean-turn transaction') -lt 1) {
    throw "V7 transaction arm disappeared."
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StageDir = "$env:USERPROFILE\Desktop\forge-v119-luna-v7-monitor-txn-v1m-$Stamp"
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

$V1iBackup = Join-Path $StageDir "run-attempt-FUyOjGCV.v1i-backup.js"
$Candidate = Join-Path $StageDir "run-attempt-FUyOjGCV.v1m-candidate.js"

[IO.File]::Copy($RunAttempt, $V1iBackup, $true)
if ((Sha256 $V1iBackup) -ne $ExpectedLiveHash) {
    throw "v1i safety backup hash mismatch."
}

[IO.File]::WriteAllText(
    $Candidate,
    $CandidateText,
    [Text.UTF8Encoding]::new($false)
)

$CandidateHash = Sha256 $Candidate

& node --check $Candidate
if ($LASTEXITCODE -ne 0) {
    throw "Staging node --check failed. Active runtime untouched."
}

# Mandatory same-package syntax probe.
$DistDir = Split-Path -Parent $RunAttempt
$PackageProbe = Join-Path $DistDir "run-attempt-FUyOjGCV.v1m-preflight-probe.js"

try {
    if (Test-Path -LiteralPath $PackageProbe) {
        Remove-Item -LiteralPath $PackageProbe -Force
    }

    [IO.File]::Copy($Candidate, $PackageProbe, $true)

    if ((Sha256 $PackageProbe) -ne $CandidateHash) {
        throw "Same-package probe hash mismatch."
    }

    & node --check $PackageProbe
    if ($LASTEXITCODE -ne 0) {
        throw "Same-package node --check failed. Active runtime untouched."
    }
}
finally {
    if (Test-Path -LiteralPath $PackageProbe) {
        Remove-Item -LiteralPath $PackageProbe -Force
    }
}

$RollbackPath = Join-Path $StageDir "ROLLBACK-V1M-TO-V1I.ps1"

$RollbackText = @"
`$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

`$RunAttempt = "$RunAttempt"
`$Backup = "$V1iBackup"
`$ExpectedHash = "$ExpectedLiveHash"

function Sha256([string]`$Path) {
    return (Get-FileHash -LiteralPath `$Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath `$Backup -PathType Leaf)) {
    throw "v1i rollback backup missing: `$Backup"
}
if ((Sha256 `$Backup) -ne `$ExpectedHash) {
    throw "v1i rollback backup hash mismatch."
}

[IO.File]::Copy(`$Backup, `$RunAttempt, `$true)

& node --check `$RunAttempt
if (`$LASTEXITCODE -ne 0) {
    throw "Restored v1i bundle failed node --check."
}
if ((Sha256 `$RunAttempt) -ne `$ExpectedHash) {
    throw "Restored v1i live SHA mismatch."
}

openclaw gateway restart
if (`$LASTEXITCODE -ne 0) {
    throw "Gateway restart failed while restoring v1i."
}

Start-Sleep -Seconds 2
openclaw gateway status --deep --require-rpc

Write-Host ""
Write-Host "PASS - restored exact v1i bundle." -ForegroundColor Green
Write-Host "Live SHA: `$(Sha256 `$RunAttempt)"
"@

[IO.File]::WriteAllText(
    $RollbackPath,
    $RollbackText,
    [Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "=== CANDIDATE ===" -ForegroundColor Cyan
Write-Host "Stage:               $StageDir"
Write-Host "Candidate SHA:       $CandidateHash"
Write-Host "Staging syntax:      PASS"
Write-Host "Same-package syntax: PASS"
Write-Host "Rollback to v1i:     powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
Write-Host ""
Write-Host "v1m changes:"
Write-Host "  - fixes v1l marker/invariant bookkeeping only; transaction design unchanged"
Write-Host "  - captures exact NO_REPLY in an independent per-run map at proven result scope"
Write-Host "  - enables the EXISTING V7 rollback/reinject transaction for Forge monitor turns"
Write-Host "  - native thread/read confirms the mapped NO_REPLY before suppressing reinjection"
Write-Host "  - normal reply: rollback dirty turn + inject clean user/assistant pair"
Write-Host "  - NO_REPLY: rollback dirty turn + inject nothing"
Write-Host "  - NO_REPLY skips transcript mirroring before transaction and binding coverage after rollback"
Write-Host "  - FINAL9 becomes bookkeeping only and cannot perform a second semantic rollback"
Write-Host "  - V7 transport, Luna sidecars, native delta and Sol are untouched"
Write-Host ""

if ($PreflightOnly) {
    Write-Host "PASS - PREFLIGHT ONLY. Active runtime bundle and gateway were not changed." -ForegroundColor Green
    exit 0
}

if ((Sha256 $RunAttempt) -ne $ExpectedLiveHash) {
    throw "Live v1i bundle changed after candidate build. Nothing modified."
}

$MutationStarted = $false

try {
    [IO.File]::Copy($Candidate, $RunAttempt, $true)
    $MutationStarted = $true

    if ((Sha256 $RunAttempt) -ne $CandidateHash) {
        throw "Live v1m hash mismatch after copy."
    }

    & node --check $RunAttempt
    if ($LASTEXITCODE -ne 0) {
        throw "Live v1m failed node --check after copy."
    }

    openclaw gateway restart
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway restart failed after v1m apply."
    }

    Start-Sleep -Seconds 2
    openclaw gateway status --deep --require-rpc
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway health check failed after v1m apply."
    }
}
catch {
    if ($MutationStarted) {
        Write-Host ""
        Write-Host "APPLY FAILED - restoring exact v1i bundle." -ForegroundColor Red
        [IO.File]::Copy($V1iBackup, $RunAttempt, $true)
        & node --check $RunAttempt | Out-Null
        try { openclaw gateway restart | Out-Host } catch {}
    }
    throw
}

Write-Host ""
Write-Host "PASS - FORGE 1.1.9 LUNA V7 MONITOR TRANSACTION v1m IS LIVE." -ForegroundColor Green
Write-Host "Live SHA:       $(Sha256 $RunAttempt)"
Write-Host "Transaction:    $TxnMarker"
Write-Host "NO_REPLY:       $NoReplyMarker"
Write-Host "FINAL9:         $Final9Marker"
Write-Host "Stage:          $StageDir"
Write-Host ""
Write-Host "Acceptance is intentionally short:"
Write-Host "  1. One normal Luna reply -> clean transaction commit log."
Write-Host "  2. One exact NO_REPLY -> exact NO_REPLY removed log, no Discord output."
Write-Host "  3. Next 3-4 turns -> input growth should be real-turn-sized, not ~0.8-1.0k staircase."