param(
    [string]$SnapshotPath = "$env:USERPROFILE\Desktop\forge-pre-silent-v119-20260922-131951",
    [string]$CandidateFolder = "$env:USERPROFILE\Downloads\forge-v119-silent-monitor-live-candidate"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedSourceCommit = 'ebf4acd23d0bbca2a2fec1edd4a0292bfb9e96f6'
$ExpectedPackageSha256 = '1fe3674b6a50a6f2e6b3694e4971a7f02ea79e6086913bf16dbc2572b58f2e69'
$PackageName = 'animeleague-forge-discord-monitor-1.1.9.tgz'
$OpenClawHome = Join-Path $env:USERPROFILE '.openclaw'
$ConfigPath = Join-Path $OpenClawHome 'openclaw.json'
$ProjectsRoot = Join-Path $OpenClawHome 'npm\projects'
$RunAttempt = Join-Path $OpenClawHome 'npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist\run-attempt-FUyOjGCV.js'
$ManifestPath = Join-Path $SnapshotPath 'manifest.json'
$Rollback = Join-Path $SnapshotPath 'ROLLBACK.ps1'
$Package = Join-Path $CandidateFolder $PackageName
$MutationStarted = $false

function Count-Literal {
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function Get-ContinuityConfig {
    param([Parameter(Mandatory=$true)]$ConfigObject)
    $entryProperty = $ConfigObject.plugins.entries.PSObject.Properties['forge-discord-monitor']
    if (-not $entryProperty) { throw 'openclaw.json has no forge-discord-monitor entry.' }
    $entry = $entryProperty.Value
    if (-not $entry.config -or -not $entry.config.continuity) {
        throw 'forge-discord-monitor continuity config is missing.'
    }
    return $entry.config.continuity
}

function Get-PluginRoots {
    if (-not (Test-Path -LiteralPath $ProjectsRoot)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $ProjectsRoot -Directory -Force |
            ForEach-Object {
                $candidate = Join-Path $_.FullName 'node_modules\@animeleague\forge-discord-monitor'
                if (Test-Path -LiteralPath $candidate) { Get-Item -LiteralPath $candidate }
            }
    )
}

try {
    Write-Host "`n=== FORGE 1.1.9 SILENT-MONITOR APPLY FROM VERIFIED PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host "Snapshot: $SnapshotPath"
    Write-Host 'This skips the recursive live plugin copy/hash that temporarily stalled Forge during preflight.'

    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Missing preflight manifest: $ManifestPath" }
    if (-not (Test-Path -LiteralPath $Rollback)) { throw "Missing rollback script: $Rollback" }
    if (-not (Test-Path -LiteralPath $Package)) { throw "Missing CI package: $Package" }
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Missing OpenClaw config: $ConfigPath" }
    if (-not (Test-Path -LiteralPath $RunAttempt)) { throw "Missing active Codex bundle: $RunAttempt" }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.sourceCommit -ne $ExpectedSourceCommit) {
        throw "Snapshot source commit mismatch. Expected $ExpectedSourceCommit, got $($manifest.sourceCommit)."
    }

    $candidatePath = [string]$manifest.candidateRunPath
    if (-not (Test-Path -LiteralPath $candidatePath)) { throw "Missing snapshot candidate Codex file: $candidatePath" }

    # Minimal freshness checks only - no recursive plugin-tree read.
    $currentConfigSha = (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $currentRunSha = (Get-FileHash -LiteralPath $RunAttempt -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentConfigSha -ne [string]$manifest.configSha256) {
        throw 'openclaw.json changed since preflight. Refusing to apply from the earlier snapshot.'
    }
    if ($currentRunSha -ne [string]$manifest.runSha256) {
        throw 'Active Codex bundle changed since preflight. Refusing to apply from the earlier snapshot.'
    }

    $packageSha = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($packageSha -ne $ExpectedPackageSha256 -or $packageSha -ne [string]$manifest.packageSha256) {
        throw "CI package SHA-256 mismatch: $packageSha"
    }
    $candidateSha = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($candidateSha -ne [string]$manifest.candidateRunSha256) {
        throw 'Snapshot candidate Codex SHA-256 mismatch.'
    }

    & node --check $candidatePath
    if ($LASTEXITCODE -ne 0) { throw 'Snapshot candidate Codex bundle failed node --check.' }

    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $continuity = Get-ContinuityConfig $cfg
    if ([int64]$continuity.nativeDeltaMaxExchanges -ne 20) { throw 'nativeDeltaMaxExchanges is no longer 20.' }
    if ([int64]$continuity.solRolloverTokens -ne 200000) { throw 'solRolloverTokens is no longer 200000.' }

    Write-Host 'Freshness check: PASS' -ForegroundColor Green
    Write-Host 'No recursive live plugin scan performed.' -ForegroundColor Green
    Write-Host "Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Rollback`""

    Write-Host "`n=== APPLY SILENT CODEX HISTORY RENDERING ===" -ForegroundColor Cyan
    $MutationStarted = $true
    Copy-Item -LiteralPath $candidatePath -Destination $RunAttempt -Force
    $liveCandidateSha = (Get-FileHash -LiteralPath $RunAttempt -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($liveCandidateSha -ne $candidateSha) { throw 'Live Codex write hash mismatch.' }
    & node --check $RunAttempt
    if ($LASTEXITCODE -ne 0) { throw 'Live patched Codex bundle failed node --check.' }

    Write-Host "`n=== INSTALL CI-TESTED MONITOR 1.1.9 ===" -ForegroundColor Cyan
    & openclaw plugins install "npm-pack:$Package" --force
    if ($LASTEXITCODE -ne 0) { throw 'Forge Monitor package install failed.' }
    & openclaw plugins enable forge-discord-monitor
    if ($LASTEXITCODE -ne 0) { throw 'Forge Monitor plugin enable failed.' }
    & openclaw config validate
    if ($LASTEXITCODE -ne 0) { throw 'OpenClaw config validation failed after package install.' }

    $postCfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $postContinuity = Get-ContinuityConfig $postCfg
    if ([int64]$postContinuity.nativeDeltaMaxExchanges -ne 20) { throw 'Package install changed nativeDeltaMaxExchanges away from 20.' }
    if ([int64]$postContinuity.solRolloverTokens -ne 200000) { throw 'Package install changed solRolloverTokens away from 200000.' }

    # Small targeted compiled-file check only - no recursive hash.
    $silentPackageFound = $false
    foreach ($root in @(Get-PluginRoots)) {
        $adapter = Join-Path $root.FullName 'dist\adapter.js'
        if (-not (Test-Path -LiteralPath $adapter)) { continue }
        $adapterText = [System.IO.File]::ReadAllText($adapter)
        if (
            (Count-Literal $adapterText 'description: "Discord moderation action."') -eq 1 -and
            (Count-Literal $adapterText 'Type.Literal("alert_staff")') -eq 0 -and
            (Count-Literal $adapterText 'Decide whether help is useful') -eq 0 -and
            (Count-Literal $adapterText 'Never announce or mention Luna') -eq 0 -and
            (Count-Literal $adapterText '[review-id:${moderationReviewId}]') -eq 1
        ) { $silentPackageFound = $true }
    }
    if (-not $silentPackageFound) { throw 'Installed plugin roots do not contain the CI-tested silent-monitor build.' }

    Write-Host "`n=== ONE GATEWAY RESTART ===" -ForegroundColor Cyan
    & openclaw gateway restart
    if ($LASTEXITCODE -ne 0) { throw 'Gateway restart failed.' }
    & openclaw gateway status
    if ($LASTEXITCODE -ne 0) { throw 'Gateway status failed after restart.' }

    $finalRun = [System.IO.File]::ReadAllText($RunAttempt)
    if ((Count-Literal $finalRun '// FORGE_CODEX_SILENT_DISCORD_HISTORY_V1') -ne 1) { throw 'Silent history marker disappeared after restart.' }
    if ((Count-Literal $finalRun 'never disclose private contents into public channels') -ne 0) { throw 'Behavioural privacy text reappeared after restart.' }
    if ((Count-Literal $finalRun 'FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1') -ne 0) { throw 'Fresh-Sol 20k marker unexpectedly appeared.' }

    Write-Host "`nPASS - 1.1.9 SILENT-MONITOR CANDIDATE IS LIVE." -ForegroundColor Green
    Write-Host 'Monitor behavioural prompt prose: removed'
    Write-Host 'Forge tool actions: warn + timeout only'
    Write-Host 'Forge warn/timeout staff report: deterministic'
    Write-Host 'Deterministic anti-spam/scammer systems: retained'
    Write-Host 'Native Sol <-> Luna cap/dedupe: unchanged at 20'
    Write-Host 'DM/public history: neutral provenance only'
    Write-Host 'Fresh-Sol 20k work: NOT included'
    Write-Host ('Rollback: powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $Rollback) -ForegroundColor Yellow
}
catch {
    Write-Host "`nINSTALL FAILED." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($MutationStarted -and (Test-Path -LiteralPath $Rollback)) {
        Write-Host 'Mutation had started - invoking exact preflight rollback now.' -ForegroundColor Yellow
        try {
            powershell -NoProfile -ExecutionPolicy Bypass -File $Rollback
            if ($LASTEXITCODE -ne 0) { throw "Rollback process exited with code $LASTEXITCODE." }
            Write-Host 'ROLLBACK COMPLETED.' -ForegroundColor Green
        }
        catch {
            Write-Host "AUTOMATIC ROLLBACK FAILED: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ('Manual rollback: powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $Rollback) -ForegroundColor Yellow
        }
    }
    else {
        Write-Host 'No live mutation had started.' -ForegroundColor Yellow
    }
    exit 1
}