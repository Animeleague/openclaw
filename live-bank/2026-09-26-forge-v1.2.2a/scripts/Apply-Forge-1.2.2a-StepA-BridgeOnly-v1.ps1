param(
    [ValidateSet("preflight","apply")]
    [string]$Action = "preflight"
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
    $at = 0
    while ($true) {
        $i = $Text.IndexOf($Needle, $at, [System.StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $count++
        $at = $i + $Needle.Length
    }
    return $count
}

function Get-StringLeaves($Value) {
    if ($null -eq $Value) { return }
    if ($Value -is [string]) { Write-Output $Value; return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { Get-StringLeaves $Value[$key] }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { Get-StringLeaves $item }
        return
    }
    foreach ($prop in $Value.PSObject.Properties) { Get-StringLeaves $prop.Value }
}

function Get-PluginInspectRaw {
    $raw = (& openclaw plugins inspect forge-discord-monitor --json | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "Could not inspect forge-discord-monitor."
    }
    return $raw
}

function Resolve-PluginRoot([string]$InspectRaw) {
    $obj = $InspectRaw | ConvertFrom-Json
    $paths = @(
        Get-StringLeaves $obj |
            Where-Object {
                $_ -match 'forge-discord-monitor' -and
                $_ -match '[\\/]dist[\\/]index\.js$'
            } |
            ForEach-Object {
                $candidate = $_
                if ($candidate -match '^file:') {
                    try { $candidate = ([Uri]$candidate).LocalPath } catch {}
                }
                $candidate
            } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -Unique
    )
    if ($paths.Count -ne 1) {
        $paths | ForEach-Object { Write-Host "  candidate: $_" }
        throw "Expected exactly one live forge-discord-monitor dist/index.js path; found $($paths.Count)."
    }
    return Split-Path -Parent (Split-Path -Parent $paths[0])
}

function Get-JsDistManifest([string]$Root) {
    $dist = Join-Path $Root "dist"
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $rows = @()
    Get-ChildItem -LiteralPath $dist -File -Recurse |
        Where-Object { $_.Extension -in @(".js", ".mjs", ".cjs") } |
        Sort-Object FullName |
        ForEach-Object {
            $full = [IO.Path]::GetFullPath($_.FullName)
            $relative = $full.Substring($rootFull.Length).TrimStart('\','/').Replace('\','/')
            $rows += "$relative`t$(Sha256 $_.FullName)"
        }
    return $rows
}

function Wait-GatewayHealthy([int]$TimeoutSeconds = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        & openclaw gateway status --deep --require-rpc
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Remove-WorktreeBestEffort([string]$Repo, [string]$Path) {
    if (-not $Path) { return }
    try { & git -C $Repo worktree remove --force $Path 2>$null | Out-Null } catch {}
    try { & git -C $Repo worktree prune 2>$null | Out-Null } catch {}
}

$ExpectedCodex121 = "9afaf1903efe3958940df446db9b0d71b0e01d5b820f869a1197e70f9452da96"
$RunAttempt = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist\run-attempt-FUyOjGCV.js"
$Config = "$env:USERPROFILE\.openclaw\openclaw.json"

$MonitorRepo = "$env:USERPROFILE\Desktop\forge-discord-monitor-v1.1.3"
$MonitorCommit = "ebf4acd23d0bbca2a2fec1edd4a0292bfb9e96f6"
$ExpectedMonitorVersion = "1.1.9"
$BridgeMarker = "FORGE_LIVE_ROOM_CONTEXT_BRIDGE_V122A"
$PermanentResidentMarker = "FORGE_PERMANENT_RESIDENT_DM_LUNA_V1"

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ScratchRoot = Join-Path $env:USERPROFILE ("f122bridge-" + $Stamp)
$BaselineWorktree = Join-Path $ScratchRoot "b"
$CandidateWorktree = Join-Path $ScratchRoot "c"
$StageDir = "$env:USERPROFILE\Desktop\forge-v122a-bridge-$Stamp"

Write-Host ""
Write-Host "=== FORGE 1.2.2a STEP A - ROOM BRIDGE ONLY ===" -ForegroundColor Cyan
Write-Host "Action: $Action"
Write-Host "Codex mutation: NONE"
Write-Host "Config mutation: NONE"
Write-Host "Plugin registry mutation: NONE"
Write-Host "Permanent Resident routing: MUST REMAIN ABSENT"
Write-Host ""

if ((Sha256 $RunAttempt) -ne $ExpectedCodex121) {
    throw "Codex is not exact banked 1.2.1 ($ExpectedCodex121). Nothing changed."
}

if (-not (Wait-GatewayHealthy 30)) {
    throw "Gateway is not healthy before staging. Nothing changed."
}

$InspectRaw = Get-PluginInspectRaw
$Inspect = $InspectRaw | ConvertFrom-Json
if ([string]$Inspect.plugin.version -ne $ExpectedMonitorVersion) {
    throw "Expected monitor 1.1.9, found $($Inspect.plugin.version). Nothing changed."
}
if ([string]$Inspect.plugin.status -ne "loaded") {
    throw "Monitor is not loaded before staging. Nothing changed."
}
$LiveRoot = Resolve-PluginRoot $InspectRaw
$LiveAdapter = Join-Path $LiveRoot "dist\adapter.js"
if (-not (Test-Path -LiteralPath $LiveAdapter -PathType Leaf)) {
    throw "Live adapter.js missing: $LiveAdapter"
}

$LiveAdapterText = [IO.File]::ReadAllText($LiveAdapter)
if ($LiveAdapterText.Contains($BridgeMarker) -or $LiveAdapterText.Contains('forge.live-room-context.v1')) {
    throw "Room bridge already appears live. Stop and reassess."
}
if ($LiveAdapterText.Contains($PermanentResidentMarker)) {
    throw "Permanent Resident routing is unexpectedly already live. Stop and reassess."
}

$rolloverRaw = (& openclaw config get plugins.entries.forge-discord-monitor.config.continuity.solRolloverTokens --json | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $rolloverRaw -ne "80000") {
    throw "Expected live Sol rollover config 80000, got '$rolloverRaw'. Nothing changed."
}

$InitialConfigHash = Sha256 $Config
$LiveAdapterHash = Sha256 $LiveAdapter

New-Item -ItemType Directory -Force -Path $StageDir, $ScratchRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $StageDir "plugin-inspect-before.json"), $InspectRaw, [Text.UTF8Encoding]::new($false))

& git -C $MonitorRepo fetch origin
if ($LASTEXITCODE -ne 0) { throw "git fetch failed. Nothing changed." }
& git -C $MonitorRepo cat-file -e "$MonitorCommit^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Pinned 1.1.9 commit missing. Nothing changed." }
& git -C $MonitorRepo worktree prune
if ($LASTEXITCODE -ne 0) { throw "git worktree prune failed. Nothing changed." }

try {
    Write-Host ""
    Write-Host "=== BASELINE 1.1.9 ===" -ForegroundColor Cyan
    & git -C $MonitorRepo worktree add --detach $BaselineWorktree $MonitorCommit
    if ($LASTEXITCODE -ne 0) { throw "Could not create baseline worktree." }

    Push-Location -LiteralPath $BaselineWorktree
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "Baseline npm ci failed." }
        & npm run check
        if ($LASTEXITCODE -ne 0) { throw "Baseline 1.1.9 test/check failed." }
    } finally { Pop-Location }

    $BaselineSource = [IO.File]::ReadAllText((Join-Path $BaselineWorktree "src\adapter.ts"))
    if ($BaselineSource.Contains($PermanentResidentMarker)) {
        throw "Pinned 1.1.9 source unexpectedly contains Permanent Resident routing."
    }

    $LiveManifest = @(Get-JsDistManifest $LiveRoot)
    $BaselineManifest = @(Get-JsDistManifest $BaselineWorktree)
    if (($LiveManifest -join "`n") -ne ($BaselineManifest -join "`n")) {
        throw "Live monitor JS does not exactly match maintained 1.1.9 baseline. Nothing changed."
    }
    Write-Host "PASS - live monitor JS exactly matches maintained 1.1.9."

    Write-Host ""
    Write-Host "=== CANDIDATE BRIDGE BUILD ===" -ForegroundColor Cyan
    & git -C $MonitorRepo worktree add --detach $CandidateWorktree $MonitorCommit
    if ($LASTEXITCODE -ne 0) { throw "Could not create candidate worktree." }

    Push-Location -LiteralPath $CandidateWorktree
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "Candidate npm ci failed." }
    } finally { Pop-Location }

    $AdapterTs = Join-Path $CandidateWorktree "src\adapter.ts"
    $source = [IO.File]::ReadAllText($AdapterTs)
    $decl = '  const liveRoomContextDiagnostics = new Map<string, LiveRoomContextDiagnostic>();'
    if ((Count-Literal $source $decl) -ne 1) {
        throw "Expected exactly one room diagnostic Map declaration."
    }

    $insert = @'
  const liveRoomContextDiagnostics = new Map<string, LiveRoomContextDiagnostic>();
  // FORGE_LIVE_ROOM_CONTEXT_BRIDGE_V122A
  // Export the exact already-generated bounded room chronology by runId.
  // Transport-only bridge: no extra model-visible text, no policy, no persistence.
  (globalThis as unknown as Record<PropertyKey, unknown>)[
    Symbol.for("forge.live-room-context.v1")
  ] = {
    pendingRuns: liveRoomContextDiagnostics
  };
'@
    $source = $source.Replace($decl, $insert)
    [IO.File]::WriteAllText($AdapterTs, $source, [Text.UTF8Encoding]::new($false))

    Push-Location -LiteralPath $CandidateWorktree
    try {
        & git diff --check
        if ($LASTEXITCODE -ne 0) { throw "Bridge source failed git diff --check." }
        & npm run check
        if ($LASTEXITCODE -ne 0) { throw "Bridge candidate test/check failed." }
    } finally { Pop-Location }

    $BaselineAdapter = Join-Path $BaselineWorktree "dist\adapter.js"
    $CandidateAdapter = Join-Path $CandidateWorktree "dist\adapter.js"
    if (-not (Test-Path -LiteralPath $BaselineAdapter -PathType Leaf)) { throw "Baseline adapter.js missing." }
    if (-not (Test-Path -LiteralPath $CandidateAdapter -PathType Leaf)) { throw "Candidate adapter.js missing." }

    $baseJs = [IO.File]::ReadAllText($BaselineAdapter)
    $candJs = [IO.File]::ReadAllText($CandidateAdapter)

    if ($candJs.Contains($PermanentResidentMarker)) {
        throw "Candidate compiled adapter unexpectedly contains Permanent Resident routing."
    }
    if ((Count-Literal $candJs $BridgeMarker) -ne 1) {
        throw "Candidate compiled bridge marker count is not exactly one."
    }
    if ((Count-Literal $candJs 'forge.live-room-context.v1') -ne 1) {
        throw "Candidate compiled bridge symbol count is not exactly one."
    }

    # Strong compiled-diff proof: outside the single inserted bridge block,
    # candidate adapter.js must be byte-for-byte text-identical to baseline.
    $compiledDecl = "const liveRoomContextDiagnostics = new Map();"
    $compiledNext = "let lastLiveRoomContextDiagnosticResult;"
    $bDecl = $baseJs.IndexOf($compiledDecl, [System.StringComparison]::Ordinal)
    $cDecl = $candJs.IndexOf($compiledDecl, [System.StringComparison]::Ordinal)
    $bNext = $baseJs.IndexOf($compiledNext, $bDecl, [System.StringComparison]::Ordinal)
    $cNext = $candJs.IndexOf($compiledNext, $cDecl, [System.StringComparison]::Ordinal)
    if ($bDecl -lt 0 -or $cDecl -lt 0 -or $bNext -lt 0 -or $cNext -lt 0) {
        throw "Could not prove compiled bridge insertion boundaries."
    }

    $bPrefixEnd = $bDecl + $compiledDecl.Length
    $cPrefixEnd = $cDecl + $compiledDecl.Length
    if ($baseJs.Substring(0, $bPrefixEnd) -cne $candJs.Substring(0, $cPrefixEnd)) {
        throw "Candidate differs from baseline before bridge insertion."
    }
    if ($baseJs.Substring($bNext) -cne $candJs.Substring($cNext)) {
        throw "Candidate differs from baseline after bridge insertion."
    }

    $insertedCompiled = $candJs.Substring($cPrefixEnd, $cNext - $cPrefixEnd)
    if (-not $insertedCompiled.Contains($BridgeMarker) -or
        -not $insertedCompiled.Contains('Symbol.for("forge.live-room-context.v1")') -or
        -not $insertedCompiled.Contains("pendingRuns: liveRoomContextDiagnostics")) {
        throw "Inserted compiled block is not the expected bridge-only block."
    }

    & node --check $CandidateAdapter
    if ($LASTEXITCODE -ne 0) { throw "Candidate adapter.js failed node --check." }

    $CandidateHash = Sha256 $CandidateAdapter
    Write-Host "Candidate adapter SHA: $CandidateHash"
    Write-Host "PASS - compiled candidate differs from exact live 1.1.9 ONLY by the bridge insertion."

    # Final live-state recheck after potentially lengthy builds/tests.
    if ((Sha256 $RunAttempt) -ne $ExpectedCodex121) {
        throw "Codex changed during staging. Nothing applied."
    }
    if ((Sha256 $Config) -ne $InitialConfigHash) {
        throw "Config changed during staging. Nothing applied."
    }
    $Inspect2Raw = Get-PluginInspectRaw
    $Inspect2 = $Inspect2Raw | ConvertFrom-Json
    $LiveRoot2 = Resolve-PluginRoot $Inspect2Raw
    if ([IO.Path]::GetFullPath($LiveRoot2) -ne [IO.Path]::GetFullPath($LiveRoot)) {
        throw "Live plugin root changed during staging. Nothing applied."
    }
    if ([string]$Inspect2.plugin.version -ne "1.1.9" -or [string]$Inspect2.plugin.status -ne "loaded") {
        throw "Live monitor state changed during staging. Nothing applied."
    }
    if ((Sha256 $LiveAdapter) -ne $LiveAdapterHash) {
        throw "Live adapter changed during staging. Nothing applied."
    }

    if ($Action -eq "preflight") {
        Write-Host ""
        Write-Host "PASS - BRIDGE-ONLY PREFLIGHT. NOTHING LIVE CHANGED." -ForegroundColor Green
        Write-Host "Codex remains exact 1.2.1: $ExpectedCodex121"
        Write-Host "Monitor remains exact live 1.1.9."
        Write-Host "Permanent Resident routing remains absent."
        return
    }

    Write-Host ""
    Write-Host "=== APPLY BRIDGE ONLY ===" -ForegroundColor Cyan

    $BackupDir = "$env:USERPROFILE\Desktop\forge-pre-v122a-bridge-$Stamp"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    [IO.File]::Copy($LiveAdapter, (Join-Path $BackupDir "adapter.js"), $true)
    [IO.File]::WriteAllText((Join-Path $BackupDir "live-plugin-root.txt"), $LiveRoot, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $BackupDir "adapter-sha-before.txt"), $LiveAdapterHash, [Text.UTF8Encoding]::new($false))

    if ((Sha256 (Join-Path $BackupDir "adapter.js")) -ne $LiveAdapterHash) {
        throw "Bridge rollback snapshot hash mismatch. Nothing applied."
    }

    $RollbackPath = Join-Path $BackupDir "ROLLBACK.ps1"
    $rollback = @'
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = [IO.File]::ReadAllText((Join-Path $Here "live-plugin-root.txt")).Trim()
$Adapter = Join-Path $Root "dist\adapter.js"
$Expected = [IO.File]::ReadAllText((Join-Path $Here "adapter-sha-before.txt")).Trim()
try { & openclaw gateway stop | Out-Host } catch {}
[IO.File]::Copy((Join-Path $Here "adapter.js"), $Adapter, $true)
if ((Sha256 $Adapter) -ne $Expected) { throw "Restored adapter hash mismatch." }
& node --check $Adapter
if ($LASTEXITCODE -ne 0) { throw "Restored adapter failed node --check." }
& openclaw gateway restart
if ($LASTEXITCODE -ne 0) { throw "Gateway restart failed during rollback." }
$deadline=(Get-Date).AddSeconds(120)
$ok=$false
while ((Get-Date) -lt $deadline) {
    & openclaw gateway status --deep --require-rpc
    if ($LASTEXITCODE -eq 0) { $ok=$true; break }
    Start-Sleep -Seconds 5
}
if (-not $ok) { throw "Gateway not healthy after rollback." }
Write-Host "ROLLBACK PASS - original monitor 1.1.9 adapter restored." -ForegroundColor Green
'@
    [IO.File]::WriteAllText($RollbackPath, $rollback, [Text.UTF8Encoding]::new($false))

    $mutated = $false
    try {
        & openclaw gateway stop
        if ($LASTEXITCODE -ne 0) { throw "Gateway stop failed." }

        $mutated = $true
        [IO.File]::Copy($CandidateAdapter, $LiveAdapter, $true)
        if ((Sha256 $LiveAdapter) -ne $CandidateHash) {
            throw "Live bridge adapter hash mismatch after copy."
        }
        $applied = [IO.File]::ReadAllText($LiveAdapter)
        if ((Count-Literal $applied $BridgeMarker) -ne 1 -or
            (Count-Literal $applied 'forge.live-room-context.v1') -ne 1) {
            throw "Applied bridge markers invalid."
        }
        if ($applied.Contains($PermanentResidentMarker)) {
            throw "Permanent Resident routing appeared unexpectedly."
        }

        & node --check $LiveAdapter
        if ($LASTEXITCODE -ne 0) { throw "Applied adapter failed node --check." }

        & openclaw gateway restart
        if ($LASTEXITCODE -ne 0) { throw "Gateway restart failed." }
        if (-not (Wait-GatewayHealthy 120)) {
            throw "Gateway failed health check after bridge apply."
        }

        $PostInspectRaw = Get-PluginInspectRaw
        $PostInspect = $PostInspectRaw | ConvertFrom-Json
        if ([string]$PostInspect.plugin.version -ne "1.1.9" -or
            [string]$PostInspect.plugin.status -ne "loaded") {
            throw "Monitor 1.1.9 is not loaded after bridge apply."
        }
        if ((Sha256 $RunAttempt) -ne $ExpectedCodex121) {
            throw "Codex 1.2.1 changed unexpectedly during bridge apply."
        }
    } catch {
        if ($mutated) {
            Write-Host "BRIDGE APPLY FAILED - rolling adapter back." -ForegroundColor Red
            try { & powershell -NoProfile -ExecutionPolicy Bypass -File $RollbackPath | Out-Host }
            catch {
                Write-Host "Automatic rollback failed. Manual rollback:" -ForegroundColor Red
                Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
            }
        }
        throw
    }

    Write-Host ""
    Write-Host "PASS - 1.2.2a STEP A ROOM BRIDGE IS LIVE." -ForegroundColor Green
    Write-Host "Monitor: 1.1.9, same registered plugin root"
    Write-Host "Codex: exact 1.2.1 unchanged"
    Write-Host "Permanent Resident routing: absent"
    Write-Host "Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
}
finally {
    Remove-WorktreeBestEffort -Repo $MonitorRepo -Path $CandidateWorktree
    Remove-WorktreeBestEffort -Repo $MonitorRepo -Path $BaselineWorktree
}