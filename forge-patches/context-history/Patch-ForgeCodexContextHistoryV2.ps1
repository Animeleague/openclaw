param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Status","Apply","Rollback")]
    [string]$Mode = "Status"
)

$ErrorActionPreference = "Stop"

$PatchName = "Forge Codex Context History V2"
$V1Marker = "FORGE_CONTEXT_HISTORY_V1"
$V2Marker = "FORGE_CONTEXT_HISTORY_V2"

$Root = Join-Path $env:APPDATA "npm\node_modules\openclaw"
$Dist = Join-Path $Root "dist"
$PatchDir = Join-Path $Root ".forge-patches\context-history-v2"
$ManifestPath = Join-Path $PatchDir "manifest.json"

$OldGuard = '        if (activeContextEngine || !promptContextRange) return;'
$NewGuard = '        if (!promptContextRange) return; /* FORGE_CONTEXT_HISTORY_V2 */'

function Get-OpenClawVersion {
    $PackagePath = Join-Path $Root "package.json"
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "OpenClaw package.json not found: $PackagePath"
    }
    return [string]((Get-Content -LiteralPath $PackagePath -Raw | ConvertFrom-Json).version)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Count-Literal([string]$Text, [string]$Needle) {
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function Assert-NodeSyntax([string]$Path) {
    & node --check $Path | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "node --check failed: $Path"
    }
}

function Resolve-RunBundle {
    $Matches = @()
    foreach ($File in Get-ChildItem -LiteralPath $Dist -File -Filter "run-attempt-*.js" -ErrorAction Stop) {
        $Text = [System.IO.File]::ReadAllText($File.FullName)
        if ($Text.Contains($V1Marker)) {
            $Matches += $File.FullName
        }
    }

    if ($Matches.Count -ne 1) {
        throw "Expected exactly one live run-attempt bundle containing $V1Marker; found $($Matches.Count). Nothing changed."
    }

    return [string]$Matches[0]
}

$Version = Get-OpenClawVersion
if ($Version -ne "2026.7.1") {
    throw "This patch is pinned to OpenClaw 2026.7.1. Found $Version. Nothing changed."
}

$RunFile = Resolve-RunBundle
$BackupPath = Join-Path $PatchDir ([IO.Path]::GetFileName($RunFile) + ".pre-v2.bak")
$RunText = [System.IO.File]::ReadAllText($RunFile)

$V1Count = Count-Literal $RunText $V1Marker
$V2Count = Count-Literal $RunText $V2Marker
$OldCount = Count-Literal $RunText $OldGuard
$NewCount = Count-Literal $RunText $NewGuard

function Show-Status {
    Write-Host ""
    Write-Host $PatchName
    Write-Host ("=" * $PatchName.Length)
    Write-Host "OpenClaw version : $Version"
    Write-Host "Run bundle       : $RunFile"
    Write-Host "Run SHA256       : $(Get-Sha256 $RunFile)"
    Write-Host "V1 marker count  : $V1Count"
    Write-Host "V2 marker count  : $V2Count"
    Write-Host "V1 guard count   : $OldCount"
    Write-Host "V2 guard count   : $NewCount"
    Write-Host "Rollback state   : $(Test-Path -LiteralPath $ManifestPath)"
    Write-Host ""

    if ($V1Count -ge 1 -and $V2Count -eq 1 -and $OldCount -eq 0 -and $NewCount -eq 1) {
        Write-Host "STATUS: INSTALLED"
    }
    elseif ($V1Count -ge 1 -and $V2Count -eq 0 -and $OldCount -eq 1 -and $NewCount -eq 0) {
        Write-Host "STATUS: READY TO APPLY"
    }
    else {
        Write-Host "STATUS: PARTIAL / UNEXPECTED - do not apply or restart until inspected"
    }
    Write-Host ""
}

if ($Mode -eq "Status") {
    Show-Status
    exit 0
}

if ($Mode -eq "Rollback") {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Rollback manifest missing: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "Rollback backup missing: $BackupPath"
    }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$Manifest.target -ne $RunFile) {
        throw "Rollback manifest target does not match the current run bundle."
    }

    $CurrentHash = Get-Sha256 $RunFile
    $ExpectedPatched = ([string]$Manifest.patchedSha256).ToLowerInvariant()
    if ($CurrentHash -ne $ExpectedPatched) {
        throw "Run bundle changed after Context History V2 was applied. Roll back later patches first; refusing to overwrite newer edits."
    }

    $BackupHash = Get-Sha256 $BackupPath
    $ExpectedOriginal = ([string]$Manifest.originalSha256).ToLowerInvariant()
    if ($BackupHash -ne $ExpectedOriginal) {
        throw "V2 backup SHA256 does not match the manifest. Refusing rollback."
    }

    Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $RestoredHash = Get-Sha256 $RunFile
    if ($RestoredHash -ne $ExpectedOriginal) {
        throw "Rollback verification failed: restored SHA256 mismatch."
    }

    Write-Host ""
    Write-Host "CONTEXT HISTORY V2 ROLLBACK PASS"
    Write-Host "Restored the exact V1/pre-V2 run bundle."
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
    exit 0
}

if ($V1Count -lt 1) {
    throw "$V1Marker is not present. Install Context History V1 first."
}

if ($V2Count -eq 1 -and $OldCount -eq 0 -and $NewCount -eq 1) {
    Write-Host "Context History V2 is already installed; no changes made."
    Show-Status
    exit 0
}

if ($V2Count -ne 0 -or $OldCount -ne 1 -or $NewCount -ne 0) {
    throw "V2 preflight failed. Expected V2 marker=0, V1 guard=1, V2 guard=0. Nothing changed."
}

$Patched = $RunText.Replace($OldGuard, $NewGuard)

if ((Count-Literal $Patched $V2Marker) -ne 1) {
    throw "In-memory V2 validation failed: marker count is not 1. Nothing changed."
}
if ((Count-Literal $Patched $OldGuard) -ne 0 -or (Count-Literal $Patched $NewGuard) -ne 1) {
    throw "In-memory V2 guard validation failed. Nothing changed."
}
if (-not $Patched.Contains($V1Marker)) {
    throw "In-memory V2 validation failed: V1 carrier marker disappeared. Nothing changed."
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null
if ((Test-Path -LiteralPath $ManifestPath) -or (Test-Path -LiteralPath $BackupPath)) {
    throw "V2 rollback state already exists at $PatchDir. Refusing to overwrite it."
}

$OriginalHash = Get-Sha256 $RunFile
Copy-Item -LiteralPath $RunFile -Destination $BackupPath

$Temp = "$RunFile.$V2Marker.tmp.js"
try {
    [System.IO.File]::WriteAllText($Temp, $Patched, [System.Text.UTF8Encoding]::new($false))
    Assert-NodeSyntax $Temp
    Move-Item -LiteralPath $Temp -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $Verify = [System.IO.File]::ReadAllText($RunFile)
    if ((Count-Literal $Verify $V2Marker) -ne 1 -or -not $Verify.Contains($V1Marker)) {
        throw "Post-write Context History V2 verification failed."
    }

    $PatchedHash = Get-Sha256 $RunFile
    [ordered]@{
        patch = $PatchName
        marker = $V2Marker
        openClawVersion = $Version
        target = $RunFile
        backup = $BackupPath
        originalSha256 = $OriginalHash
        patchedSha256 = $PatchedHash
        change = "Allow the proven Context History V1 carrier whenever promptContextRange exists, including when an external context engine is active."
        reconstructedFromLiveRuntime = "2026-08-13"
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "CONTEXT HISTORY V2 APPLY PASS"
    Write-Host ""
    Write-Host "Behavior:"
    Write-Host "  V1 carrier logic is unchanged."
    Write-Host "  V2 removes only the activeContextEngine skip."
    Write-Host "  Historical conversation_context remains untrusted additionalContext."
    Write-Host "  Durable user prompt still has the duplicated history removed."
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
}
catch {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $BackupPath) {
        Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    }
    throw
}
