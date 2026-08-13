param(
    [ValidateSet("Status","Apply","Rollback")]
    [string]$Mode = "Status"
)

$ErrorActionPreference = "Stop"

$PatchName = "Forge Monitor Transient Context V1.3"
$Root = Join-Path $env:APPDATA "npm\node_modules\openclaw"
$Dist = Join-Path $Root "dist"
$PatchDir = Join-Path $Root ".forge-patches\monitor-transient-context-v1_3"
$ManifestPath = Join-Path $PatchDir "manifest.json"

$OldNeedle = 'const monitorHeader = "[Forge Discord Monitor —";'
$NewNeedle = 'const monitorHeader = "[Forge Discord Monitor";'
$Marker = "FORGE_MONITOR_TRANSIENT_CONTEXT_V1"

function Get-OpenClawVersion {
    $packagePath = Join-Path $Root "package.json"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "OpenClaw package.json not found at $packagePath"
    }
    return (Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json).version
}

function Count-Occurrences {
    param([string]$Text, [string]$Needle)
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

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-NodeSyntax {
    param([string]$Path)
    & node --check $Path | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "node --check failed for $Path"
    }
}

function Resolve-RunBundleFast {
    # V1.2 already has the monitor transient marker in exactly one live OpenClaw JS bundle.
    $matches = @()
    foreach ($file in Get-ChildItem -LiteralPath $Dist -File -Filter "run-attempt-*.js") {
        $txt = [System.IO.File]::ReadAllText($file.FullName)
        if ($txt.Contains($Marker)) {
            $matches += $file.FullName
        }
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one run-attempt bundle containing $Marker; found $($matches.Count). Nothing changed."
    }
    return [string]$matches[0]
}

$version = Get-OpenClawVersion
if ($version -ne "2026.7.1") {
    throw "This patch is pinned to OpenClaw 2026.7.1. Found $version. Nothing changed."
}

$RunFile = Resolve-RunBundleFast
$runText = [System.IO.File]::ReadAllText($RunFile)
$oldCount = Count-Occurrences $runText $OldNeedle
$newCount = Count-Occurrences $runText $NewNeedle
$markerCount = Count-Occurrences $runText $Marker
$BackupPath = Join-Path $PatchDir ([IO.Path]::GetFileName($RunFile) + ".bak")

function Show-Status {
    Write-Host ""
    Write-Host "# $PatchName"
    Write-Host ""
    Write-Host "OpenClaw version : $version"
    Write-Host "Run bundle       : $RunFile"
    Write-Host "Run SHA256       : $(Get-Sha256 $RunFile)"
    Write-Host "V1 marker        : $markerCount"
    Write-Host "Old strict header: $oldCount"
    Write-Host "New prefix header: $newCount"
    Write-Host ""
    if ($oldCount -eq 1 -and $newCount -eq 0 -and $markerCount -eq 1) {
        Write-Host "State: READY"
    } elseif ($oldCount -eq 0 -and $newCount -eq 1 -and $markerCount -eq 1) {
        Write-Host "State: PATCHED"
    } else {
        Write-Host "State: NOT READY - Apply will refuse."
    }
    Write-Host "Backup directory : $PatchDir"
    Write-Host ""
}

if ($Mode -eq "Status") {
    Show-Status
    exit 0
}

if ($Mode -eq "Rollback") {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Rollback manifest missing: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Rollback backup missing: $BackupPath"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.target -ne $RunFile) {
        throw "Manifest target does not match current run bundle. Refusing rollback."
    }

    $currentHash = Get-Sha256 $RunFile
    $expectedPatched = ([string]$manifest.patchedSha256).ToLowerInvariant()
    if ($currentHash -ne $expectedPatched) {
        throw "Current run bundle hash differs from recorded V1.3 patched hash. Refusing rollback."
    }

    Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $restoredHash = Get-Sha256 $RunFile
    $expectedOriginal = ([string]$manifest.originalSha256).ToLowerInvariant()
    if ($restoredHash -ne $expectedOriginal) {
        throw "Rollback restored file but hash does not match the recorded pre-V1.3 bundle."
    }

    Write-Host ""
    Write-Host "ROLLBACK PASS - restored V1.2 bundle."
    Write-Host ""
    exit 0
}

# APPLY
if ($markerCount -ne 1 -or $oldCount -ne 1 -or $newCount -ne 0) {
    throw "V1.3 preflight failed. Expected V1 marker=1, old strict header=1, new prefix header=0. Nothing changed."
}

$patched = $runText.Replace($OldNeedle, $NewNeedle)

if ((Count-Occurrences $patched $OldNeedle) -ne 0) {
    throw "In-memory validation failed: old strict header remains. Nothing changed."
}
if ((Count-Occurrences $patched $NewNeedle) -ne 1) {
    throw "In-memory validation failed: new prefix header count is not 1. Nothing changed."
}
if ((Count-Occurrences $patched $Marker) -ne 1) {
    throw "In-memory validation failed: V1 marker count changed unexpectedly. Nothing changed."
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null

$originalHash = Get-Sha256 $RunFile
Copy-Item -LiteralPath $RunFile -Destination $BackupPath -Force

$temp = "$RunFile.FORGE_MONITOR_TRANSIENT_CONTEXT_V1_3.tmp.js"
try {
    [System.IO.File]::WriteAllText($temp, $patched, [System.Text.UTF8Encoding]::new($false))
    Assert-NodeSyntax $temp
    Move-Item -LiteralPath $temp -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $patchedHash = Get-Sha256 $RunFile
    $manifest = [ordered]@{
        patch = $PatchName
        version = $version
        target = $RunFile
        backup = $BackupPath
        originalSha256 = $originalHash
        patchedSha256 = $patchedHash
        change = 'Relax monitor header matcher from exact em-dash form to stable "[Forge Discord Monitor" prefix.'
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "APPLY PASS"
    Write-Host "Changed monitor matcher:"
    Write-Host "  FROM: $OldNeedle"
    Write-Host "  TO  : $NewNeedle"
    Write-Host "Backup: $BackupPath"
    Write-Host "SHA256: $patchedHash"
    Write-Host ""
    Write-Host "Restart the OpenClaw gateway before testing."
    Write-Host ""
}
catch {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $BackupPath) {
        Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    }
    throw
}
