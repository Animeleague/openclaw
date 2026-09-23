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

function Replace-Once(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
) {
    $count = Count-Literal $Text $Old
    if ($count -ne 1) {
        throw "$Label - expected exactly one match, found $count."
    }
    return $Text.Replace($Old, $New)
}

$RunAttempt = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist\run-attempt-FUyOjGCV.js"

# Exact currently-live v1g candidate.
$ExpectedLiveHash = "5980b65cc8dc6b3f02b8b5cea437cc97cd793619ebad3bdb7d706a20da10a12c"

$OldMarker = "FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119G"
$NewMarker = "FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119I"
$StateMarker = "FORGE_CODEX_LUNA_NO_REPLY_ENTRY_STATE_V119I"

$V7Marker = "FORGE_CODEX_ROOM_CONTEXT_TRANSACTIONAL_V7"
$V7CommitLog = "forge transient tool transaction committed clean visible history on same native thread"

$MirrorAnchor = 'const assistantTranscriptOwned = await mirrorTranscriptBestEffort({'
$CleanupStartNeedle = 'const forgeLunaMonitorNoReplyV119G ='
$CleanupEndNeedle = 'forgeNativeMonitorCleanupStateV109?.disposableRuns?.delete(params.runId);'

Write-Host ""
Write-Host "=== FORGE 1.1.9 LUNA MONITOR SPLIT-RETENTION v1i ===" -ForegroundColor Cyan
Write-Host "Fix: exact NO_REPLY decision is stored on the existing disposable run entry"
Write-Host "Real reply: preserve V7 clean user/assistant reinjection"
Write-Host "NO_REPLY:   FINAL9 whole-turn rollback"
Write-Host "V7:         unchanged"
Write-Host "Sol:        untouched"
Write-Host ""

if (-not (Test-Path -LiteralPath $RunAttempt -PathType Leaf)) {
    throw "Active Codex bundle not found: $RunAttempt"
}

$LiveHash = Sha256 $RunAttempt
Write-Host "Live SHA: $LiveHash"

if ($LiveHash -ne $ExpectedLiveHash) {
    throw "Live SHA mismatch. Expected exact v1g $ExpectedLiveHash but found $LiveHash. Nothing modified."
}

$BaseText = [IO.File]::ReadAllText($RunAttempt)

foreach ($required in @(
    $OldMarker,
    $V7Marker,
    $V7CommitLog,
    $MirrorAnchor,
    $CleanupStartNeedle,
    $CleanupEndNeedle,
    'const attemptSucceeded =',
    'result.assistantTexts',
    'globalThis[Symbol.for("forge.native-thread-rollback.v1")]',
    '"thread/inject_items"',
    '"thread/rollback"'
)) {
    if ((Count-Literal $BaseText $required) -lt 1) {
        throw "Required live structure missing: $required"
    }
}

if ((Count-Literal $BaseText $OldMarker) -ne 1) {
    throw "Expected exactly one v1g cleanup marker."
}
if ((Count-Literal $BaseText $NewMarker) -ne 0) {
    throw "v1i cleanup marker already present."
}
if ((Count-Literal $BaseText $StateMarker) -ne 0) {
    throw "v1i state marker already present."
}
if ((Count-Literal $BaseText $V7Marker) -ne 1) {
    throw "Expected exactly one V7 room-context marker."
}
if ((Count-Literal $BaseText $MirrorAnchor) -ne 1) {
    throw "Expected exactly one transcript mirror anchor."
}
if ((Count-Literal $BaseText $CleanupStartNeedle) -ne 1) {
    throw "Expected exactly one broken v1g cleanup start."
}

# -------------------------------------------------------------------------
# 1. Capture exact NO_REPLY while result.assistantTexts is definitely in scope.
#    Store it on the ALREADY-EXISTING per-run disposable monitor entry so there
#    is no second lifecycle/map to manage.
# -------------------------------------------------------------------------

$StateInsert = @'
const forgeLunaMonitorStateV119I =
        globalThis[Symbol.for("forge.native-thread-rollback.v1")];
const forgeLunaMonitorEntryV119I =
        forgeLunaMonitorStateV119I?.disposableRuns instanceof Map
                ? forgeLunaMonitorStateV119I.disposableRuns.get(params.runId)
                : void 0;
if (forgeLunaMonitorEntryV119I?.reason === "forge-monitor") {
        forgeLunaMonitorEntryV119I.exactNoReplyV119I =
                attemptSucceeded &&
                params.allowEmptyAssistantReplyAsSilent === true &&
                Array.isArray(result.assistantTexts) &&
                result.assistantTexts.length === 1 &&
                result.assistantTexts[0]?.trim() === "NO_REPLY"; // FORGE_CODEX_LUNA_NO_REPLY_ENTRY_STATE_V119I
}
const assistantTranscriptOwned = await mirrorTranscriptBestEffort({
'@

$CandidateText = Replace-Once `
    $BaseText `
    $MirrorAnchor `
    $StateInsert `
    "NO_REPLY entry-state capture insertion"

# -------------------------------------------------------------------------
# 2. Scope from the ACTUAL start of the broken v1g expression, not from the
#    marker line. This is the boundary bug that made v1h safely stop.
# -------------------------------------------------------------------------

$Start = $CandidateText.IndexOf(
    $CleanupStartNeedle,
    [System.StringComparison]::Ordinal
)
if ($Start -lt 0) {
    throw "v1g cleanup start anchor not found after state insertion."
}

$EndAnchor = $CandidateText.IndexOf(
    $CleanupEndNeedle,
    $Start,
    [System.StringComparison]::Ordinal
)
if ($EndAnchor -lt 0) {
    throw "FINAL9 cleanup end anchor not found."
}

$End = $EndAnchor + $CleanupEndNeedle.Length
$OldBlock = $CandidateText.Substring($Start, $End - $Start)
$NewBlock = $OldBlock

$ScopedResultRefs = Count-Literal $OldBlock "result"
Write-Host "Scoped v1g result refs: $ScopedResultRefs"

# The complete broken v1g block has:
# - three result references in exact NO_REPLY detection
# - two result references in assistantTextCount diagnostic
if ($ScopedResultRefs -ne 5) {
    throw "Expected exactly 5 v1g result references in full FINAL9 scope; found $ScopedResultRefs."
}

$GateEndNeedle = 'result.assistantTexts[0]?.trim() === "NO_REPLY"; // FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119G'

$GateStart = $NewBlock.IndexOf(
    $CleanupStartNeedle,
    [System.StringComparison]::Ordinal
)
$GateEndAnchor = $NewBlock.IndexOf(
    $GateEndNeedle,
    $GateStart,
    [System.StringComparison]::Ordinal
)

if ($GateStart -lt 0 -or $GateEndAnchor -lt 0) {
    throw "Could not structurally locate complete broken v1g NO_REPLY expression."
}

$GateEnd = $GateEndAnchor + $GateEndNeedle.Length

$FixedGate = @'
const forgeLunaMonitorNoReplyV119I =
                                shouldDelayNativeHookRelayUnregister &&
                                forgeNativeMonitorCleanupEntryV109?.exactNoReplyV119I === true; // FORGE_CODEX_LUNA_MONITOR_SPLIT_RETENTION_V119I
'@

$NewBlock =
    $NewBlock.Substring(0, $GateStart) +
    $FixedGate +
    $NewBlock.Substring($GateEnd)

$NewBlock = $NewBlock.Replace(
    '!forgeLunaMonitorNoReplyV119G',
    '!forgeLunaMonitorNoReplyV119I'
)
$NewBlock = $NewBlock.Replace(
    'if (forgeLunaMonitorNoReplyV119G) {',
    'if (forgeLunaMonitorNoReplyV119I) {'
)

# -------------------------------------------------------------------------
# 3. Remove the remaining two out-of-scope result references from the
#    informational real-reply diagnostic. Locate the field structurally.
# -------------------------------------------------------------------------

$DiagStartNeedle = 'assistantTextCount:'
$DiagStart = $NewBlock.IndexOf(
    $DiagStartNeedle,
    [System.StringComparison]::Ordinal
)

if ($DiagStart -lt 0) {
    throw "Could not locate v1g assistantTextCount diagnostic."
}

$DiagEndNeedle = ': 0'
$DiagEndAnchor = $NewBlock.IndexOf(
    $DiagEndNeedle,
    $DiagStart,
    [System.StringComparison]::Ordinal
)

if ($DiagEndAnchor -lt 0) {
    throw "Could not locate end of v1g assistantTextCount diagnostic."
}

$DiagEnd = $DiagEndAnchor + $DiagEndNeedle.Length

$NewBlock =
    $NewBlock.Substring(0, $DiagStart) +
    'noReply: false' +
    $NewBlock.Substring($DiagEnd)

# FINAL9 must now be entirely independent of result scope.
if ((Count-Literal $NewBlock "result") -ne 0) {
    throw "v1i FINAL9 cleanup still contains an out-of-scope result reference."
}
if ((Count-Literal $NewBlock $OldMarker) -ne 0) {
    throw "v1i FINAL9 still contains v1g marker."
}
if ((Count-Literal $NewBlock $NewMarker) -ne 1) {
    throw "v1i FINAL9 marker count is not exactly one."
}
if ((Count-Literal $NewBlock 'forgeNativeMonitorCleanupEntryV109?.exactNoReplyV119I === true') -ne 1) {
    throw "v1i cleanup is not reading exact NO_REPLY from the disposable run entry exactly once."
}
if ((Count-Literal $NewBlock 'forgeLunaMonitorNoReplyV119I') -lt 3) {
    throw "v1i NO_REPLY boolean is not wired through both cleanup branches."
}
if ((Count-Literal $NewBlock 'client.request("thread/rollback"') -ne 1) {
    throw "v1i scoped rollback request count changed."
}
if ((Count-Literal $NewBlock 'client.request("thread/read"') -ne 1) {
    throw "v1i scoped rollback readback count changed."
}
if ((Count-Literal $NewBlock 'forge Luna monitor cleanup retained V7 clean replied turn') -ne 1) {
    throw "v1i real-reply retention diagnostic missing."
}
if ((Count-Literal $NewBlock 'forge Luna monitor cleanup rollback succeeded') -ne 1) {
    throw "v1i NO_REPLY rollback success diagnostic missing."
}
if ((Count-Literal $NewBlock 'thread.preserveNativeModel = true;') -ne 2) {
    throw "v1i should still have exactly two preserve assignments in FINAL9."
}

$CandidateText =
    $CandidateText.Substring(0, $Start) +
    $NewBlock +
    $CandidateText.Substring($End)

# Whole-candidate invariants.
if ((Count-Literal $CandidateText $OldMarker) -ne 0) {
    throw "Candidate still contains v1g marker."
}
if ((Count-Literal $CandidateText $NewMarker) -ne 1) {
    throw "Candidate v1i marker count is not exactly one."
}
if ((Count-Literal $CandidateText $StateMarker) -ne 1) {
    throw "Candidate NO_REPLY state marker count is not exactly one."
}
if ((Count-Literal $CandidateText $V7Marker) -ne 1) {
    throw "Candidate V7 marker count changed."
}
if ((Count-Literal $CandidateText $V7CommitLog) -lt 1) {
    throw "Candidate lost V7 clean-history commit path."
}
if ((Count-Literal $CandidateText 'result.assistantTexts[0]?.trim() === "NO_REPLY"') -ne 1) {
    throw "Candidate should contain exactly one exact NO_REPLY detector, in proven result scope."
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StageDir = "$env:USERPROFILE\Desktop\forge-v119-luna-monitor-split-v1i-$Stamp"
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

$V1gBackup = Join-Path $StageDir "run-attempt-FUyOjGCV.v1g-backup.js"
$Candidate = Join-Path $StageDir "run-attempt-FUyOjGCV.v1i-candidate.js"

[IO.File]::Copy($RunAttempt, $V1gBackup, $true)
if ((Sha256 $V1gBackup) -ne $ExpectedLiveHash) {
    throw "v1g safety backup hash mismatch."
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

$DistDir = Split-Path -Parent $RunAttempt
$PackageProbe = Join-Path $DistDir "run-attempt-FUyOjGCV.v1i-preflight-probe.js"

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

$RollbackPath = Join-Path $StageDir "ROLLBACK-V1I-TO-V1G.ps1"

$RollbackText = @"
`$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

`$RunAttempt = "$RunAttempt"
`$Backup = "$V1gBackup"
`$ExpectedHash = "$ExpectedLiveHash"

function Sha256([string]`$Path) {
    return (Get-FileHash -LiteralPath `$Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath `$Backup -PathType Leaf)) {
    throw "v1g rollback backup missing: `$Backup"
}
if ((Sha256 `$Backup) -ne `$ExpectedHash) {
    throw "v1g rollback backup hash mismatch."
}

[IO.File]::Copy(`$Backup, `$RunAttempt, `$true)

& node --check `$RunAttempt
if (`$LASTEXITCODE -ne 0) {
    throw "Restored v1g bundle failed node --check."
}
if ((Sha256 `$RunAttempt) -ne `$ExpectedHash) {
    throw "Restored v1g live SHA mismatch."
}

openclaw gateway restart
if (`$LASTEXITCODE -ne 0) {
    throw "Gateway restart failed while restoring v1g."
}

Start-Sleep -Seconds 2
openclaw gateway status --deep --require-rpc

Write-Host ""
Write-Host "PASS - restored exact v1g bundle." -ForegroundColor Green
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
Write-Host "Rollback to v1g:     powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
Write-Host ""
Write-Host "v1i changes:"
Write-Host "  - fixes v1h's preflight substring-boundary bug"
Write-Host "  - exact NO_REPLY is computed where result.assistantTexts is in scope"
Write-Host "  - boolean is stored on the existing disposable monitor run entry"
Write-Host "  - FINAL9 contains ZERO result references"
Write-Host "  - real Luna reply keeps V7 clean user/assistant history"
Write-Host "  - exact NO_REPLY still rolls back one clean turn"
Write-Host "  - V7 room-context transport/reinjection unchanged"
Write-Host "  - Sol untouched"
Write-Host ""

if ($PreflightOnly) {
    Write-Host "PASS - PREFLIGHT ONLY. Active runtime bundle and gateway were not changed." -ForegroundColor Green
    exit 0
}

if ((Sha256 $RunAttempt) -ne $ExpectedLiveHash) {
    throw "Live v1g bundle changed after candidate build. Nothing modified."
}

$MutationStarted = $false

try {
    [IO.File]::Copy($Candidate, $RunAttempt, $true)
    $MutationStarted = $true

    if ((Sha256 $RunAttempt) -ne $CandidateHash) {
        throw "Live v1i hash mismatch after copy."
    }

    & node --check $RunAttempt
    if ($LASTEXITCODE -ne 0) {
        throw "Live v1i failed node --check after copy."
    }

    openclaw gateway restart
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway restart failed after v1i apply."
    }

    Start-Sleep -Seconds 2
    openclaw gateway status --deep --require-rpc
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway health check failed after v1i apply."
    }
}
catch {
    if ($MutationStarted) {
        Write-Host ""
        Write-Host "APPLY FAILED - restoring exact v1g bundle." -ForegroundColor Red
        [IO.File]::Copy($V1gBackup, $RunAttempt, $true)
        & node --check $RunAttempt | Out-Null
        try { openclaw gateway restart | Out-Host } catch {}
    }
    throw
}

Write-Host ""
Write-Host "PASS - FORGE 1.1.9 LUNA MONITOR SPLIT-RETENTION v1i IS LIVE." -ForegroundColor Green
Write-Host "Live SHA:       $(Sha256 $RunAttempt)"
Write-Host "Cleanup marker: $NewMarker"
Write-Host "State marker:   $StateMarker"
Write-Host "Stage:          $StageDir"
Write-Host ""
Write-Host "Acceptance:"
Write-Host "  1. Normal Luna reply: V7 commit + retained V7 clean replied turn."
Write-Host "  2. Cross-channel recall of Luna's own previous reply works."
Write-Host "  3. Exact NO_REPLY: rollback succeeded, no Discord output."
Write-Host "  4. No 'result is not defined' cleanup failures."
Write-Host "  5. Latest-10 remains additionalContext-only."