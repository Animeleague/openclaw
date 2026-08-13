param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$PatchName = "Forge Codex Durable Registration Proof V1.1"
$Marker = "FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1"
$ExpectedSha256 = "b0e9dff28e32881f98c86edd7bb57b9641edf44079b8324c32c19f632b0cae37"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$Target = Join-Path $Dist "run-attempt-FUyOjGCV.js"

$StateDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-durable-registration-proof-v1"
$ManifestPath = Join-Path $StateDir "manifest.json"
$BackupPath = Join-Path $StateDir "run-attempt.pre-proof.js"

$RequiredMarkers = @(
    "FORGE_CODEX_STABLE_TOOL_CATALOG_V2",
    "FORGE_CODEX_TURN_PAYLOAD_DIAG_V1",
    "FORGE_CODEX_DUAL_WARM_THREADS_V2"
)

$AnchorPattern = 'registeredTools:\s*await buildDynamicTools\(\{\s*params:\s*dynamicToolParams,'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Target {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "Target not found: $Target"
    }
    return [System.IO.File]::ReadAllText($Target)
}

function Test-RequiredMarkers([string]$Text) {
    $missing = @()
    foreach ($m in $RequiredMarkers) {
        if (-not $Text.Contains($m)) { $missing += $m }
    }
    return $missing
}

function Show-Status {
    $Text = Read-Target
    $Hash = Get-Sha256 $Target
    $AnchorCount = ([regex]::Matches($Text, $AnchorPattern)).Count
    $Missing = @(Test-RequiredMarkers $Text)
    $Installed = $Text.Contains($Marker)

    Write-Host ""
    Write-Host $PatchName
    Write-Host ""
    Write-Host "Target:"
    Write-Host "  $Target"
    Write-Host ""
    Write-Host "State:"
    Write-Host "  Proof marker present:       $Installed"
    Write-Host "  Stable Tool Catalog V2:     $($Text.Contains('FORGE_CODEX_STABLE_TOOL_CATALOG_V2'))"
    Write-Host "  Turn Payload Diag V1:       $($Text.Contains('FORGE_CODEX_TURN_PAYLOAD_DIAG_V1'))"
    Write-Host "  Dual Warm Threads V2:       $($Text.Contains('FORGE_CODEX_DUAL_WARM_THREADS_V2'))"
    Write-Host "  Registration anchor count:  $AnchorCount"
    Write-Host "  Backup manifest exists:     $(Test-Path -LiteralPath $ManifestPath)"
    Write-Host "  Current SHA256:             $Hash"
    Write-Host "  Expected baseline SHA256:   $ExpectedSha256"
    Write-Host ""

    if ($Installed) {
        Write-Host "STATUS: INSTALLED"
        return
    }

    if ($Missing.Count -gt 0) {
        Write-Host "STATUS: REFUSING - required existing patch marker(s) missing:"
        $Missing | ForEach-Object { Write-Host "  $_" }
        return
    }

    if ($Hash -ne $ExpectedSha256) {
        Write-Host "STATUS: NOT SAFE TO APPLY - target hash is not the verified baseline"
        return
    }

    if ($AnchorCount -ne 1) {
        Write-Host "STATUS: NOT SAFE TO APPLY - registration anchor missing/non-unique"
        return
    }

    Write-Host "STATUS: READY TO APPLY"
}

if ($Action -eq "status") {
    Show-Status
    exit 0
}

if ($Action -eq "apply") {
    $Text = Read-Target
    $Hash = Get-Sha256 $Target

    if ($Text.Contains($Marker)) {
        throw "$PatchName is already installed."
    }

    $Missing = @(Test-RequiredMarkers $Text)
    if ($Missing.Count -gt 0) {
        throw "Required existing patch marker(s) missing: $($Missing -join ', ')"
    }

    if ($Hash -ne $ExpectedSha256) {
        throw "Refusing to patch: SHA256 $Hash does not match verified baseline $ExpectedSha256."
    }

    $Matches = [regex]::Matches($Text, $AnchorPattern)
    if ($Matches.Count -ne 1) {
        throw "Preflight failed: registration anchor occurred $($Matches.Count) times; expected 1. Nothing was modified."
    }

    $Match = $Matches[0]
    $Old = $Match.Value

    $ParamPattern = 'params:\s*dynamicToolParams,'
    $ParamMatches = [regex]::Matches($Old, $ParamPattern)
    if ($ParamMatches.Count -ne 1) {
        throw "Internal preflight failed: dynamicToolParams anchor occurred $($ParamMatches.Count) times inside registration block."
    }

    # Mirrors the corrected PR architecture:
    # - durable registered schema advertises the owner-capable superset
    # - current-turn images are removed from durable registration
    # - executable tools continue to use the untouched real dynamicToolParams
    $ReplacementParam = 'params: dynamicToolParams.senderIsOwner === true && (dynamicToolParams.images?.length ?? 0) === 0 ? dynamicToolParams : { ...dynamicToolParams, senderIsOwner: true, images: void 0 }, // FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1'
    $NewAnchor = [regex]::Replace($Old, $ParamPattern, $ReplacementParam, 1)

    $NewText = $Text.Substring(0, $Match.Index) + $NewAnchor + $Text.Substring($Match.Index + $Match.Length)

    if (-not $NewText.Contains($Marker)) {
        throw "Patch construction failed before write."
    }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    if ((Test-Path -LiteralPath $ManifestPath) -or (Test-Path -LiteralPath $BackupPath)) {
        throw "Rollback state already exists at $StateDir. Refusing to overwrite it."
    }

    Copy-Item -LiteralPath $Target -Destination $BackupPath
    $OriginalHash = Get-Sha256 $BackupPath

    $Temp = "$Target.forge-durable-registration-proof.tmp.js"
    [System.IO.File]::WriteAllText($Temp, $NewText, [System.Text.UTF8Encoding]::new($false))

    try {
        & node --check $Temp | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "node --check failed for patched run-attempt bundle."
        }

        Move-Item -LiteralPath $Temp -Destination $Target -Force

        $Verify = Read-Target
        if (-not $Verify.Contains($Marker)) {
            throw "Post-write verification failed: proof marker missing."
        }
        foreach ($m in $RequiredMarkers) {
            if (-not $Verify.Contains($m)) {
                throw "Post-write verification failed: existing marker disappeared: $m"
            }
        }

        $PatchedHash = Get-Sha256 $Target

        $Manifest = [ordered]@{
            patch = $PatchName
            marker = $Marker
            target = $Target
            backup = $BackupPath
            originalSha256 = $OriginalHash
            patchedSha256 = $PatchedHash
            appliedAt = (Get-Date).ToString("o")
        }
        $Manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    }
    catch {
        if (Test-Path -LiteralPath $Temp) {
            Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $BackupPath) {
            Copy-Item -LiteralPath $BackupPath -Destination $Target -Force
        }
        throw
    }

    Write-Host ""
    Write-Host "DURABLE REGISTRATION PROOF V1 APPLY PASS"
    Write-Host ""
    Write-Host "Behavior:"
    Write-Host "  Executable tools: real sender ownership + real current-turn images (unchanged)"
    Write-Host "  Durable registered tools: owner-capable advertised superset"
    Write-Host "  Durable registered images: neutralized"
    Write-Host "  Stable Catalog V2: preserved"
    Write-Host "  Payload diagnostics: preserved"
    Write-Host "  Dual Warm Threads V2: preserved"
    Write-Host ""
    Write-Host "SHA256:"
    Write-Host "  before: $OriginalHash"
    Write-Host "  after:  $PatchedHash"
    Write-Host ""
    Write-Host "No gateway restart has been performed by this script."
    exit 0
}

if ($Action -eq "rollback") {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Rollback manifest not found: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Rollback backup not found: $BackupPath"
    }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $CurrentHash = Get-Sha256 $Target
    $RecordedPatched = ([string]$Manifest.patchedSha256).ToLowerInvariant()

    if ($CurrentHash -ne $RecordedPatched) {
        throw "Current run-attempt hash does not match the recorded patched hash. Refusing guarded rollback."
    }

    Copy-Item -LiteralPath $BackupPath -Destination $Target -Force

    $RestoredHash = Get-Sha256 $Target
    $RecordedOriginal = ([string]$Manifest.originalSha256).ToLowerInvariant()

    if ($RestoredHash -ne $RecordedOriginal) {
        throw "Rollback copy completed but restored hash does not match the original manifest hash."
    }

    & node --check $Target | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Restored file failed node --check."
    }

    Write-Host ""
    Write-Host "DURABLE REGISTRATION PROOF V1 ROLLBACK PASS"
    Write-Host "Restored SHA256: $RestoredHash"
    Write-Host "Restart the gateway before testing the restored runtime."
    exit 0
}
