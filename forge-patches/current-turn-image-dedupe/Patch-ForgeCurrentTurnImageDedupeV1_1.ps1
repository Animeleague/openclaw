param(
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

# ============================================================
# Forge Current-Turn Image Dedupe V1
#
# Purpose:
#   Remove exact duplicate image objects at the FINAL current-turn
#   image merge, after all upstream image sources have contributed.
#
# Safety:
#   - Windows PowerShell 5.1 compatible.
#   - Requires Image Stability V1.1 to already be installed.
#   - Patches exactly ONE discovered runtime JS file.
#   - Creates an exact backup + SHA256 manifest.
#   - Does NOT modify V1.1's inbound-media or vision-tool patches.
#   - Rollback restores the exact original file.
# ============================================================

$Dist = Join-Path $env:APPDATA "npm\node_modules\openclaw\dist"
$BackupDir = Join-Path $env:USERPROFILE "Downloads\forge-current-turn-image-dedupe-v1-backup"
$Manifest = Join-Path $BackupDir "manifest.json"

$Marker = "FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1"
$FunctionNeedle = "function resolveMergedTurnImages(entries) {"
$NextAnchor = "/** Resolves current-turn image attachments"
$RequiredV11Marker = "FORGE_CODEX_IMAGE_STABILITY_V1_1"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Find-TargetFile {
    if (-not (Test-Path $Dist)) {
        throw "OpenClaw dist directory not found: $Dist"
    }

    $Matches = @(
        Get-ChildItem -Path $Dist -Recurse -File -Filter "*.js" |
        Select-String -SimpleMatch -Pattern $FunctionNeedle -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -Unique
    )

    if ($Matches.Count -ne 1) {
        Write-Host ""
        Write-Host "Found $($Matches.Count) files containing:"
        Write-Host "  $FunctionNeedle"
        foreach ($M in $Matches) {
            Write-Host "  $M"
        }
        Write-Host ""
        throw "Expected exactly 1 current-turn image merge runtime file. Nothing was changed."
    }

    return $Matches[0]
}

function Find-V11MarkerFiles {
    # Image Stability V1.1 patches the separately installed @openclaw/codex
    # project, not the global OpenClaw dist that contains resolveMergedTurnImages.
    $SearchRoots = @(
        (Join-Path $env:USERPROFILE ".openclaw\npm"),
        $Dist
    ) | Where-Object { Test-Path $_ } | Select-Object -Unique

    $Matches = @()
    foreach ($Root in $SearchRoots) {
        $Matches += @(
            Get-ChildItem -Path $Root -Recurse -File -Filter "*.js" -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch -Pattern $RequiredV11Marker -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Path -Unique
        )
    }

    return @($Matches | Select-Object -Unique)
}

function Test-V11Installed {
    return ((Find-V11MarkerFiles).Count -gt 0)
}

function Get-State {
    $Target = Find-TargetFile
    $Text = [System.IO.File]::ReadAllText($Target)

    return [pscustomobject]@{
        Target = $Target
        Patched = $Text.Contains($Marker)
        V11Installed = Test-V11Installed
        BackupExists = Test-Path $Manifest
        Sha256 = Get-Sha256 $Target
    }
}

function Show-Status {
    $State = Get-State

    Write-Host ""
    Write-Host "Forge Current-Turn Image Dedupe V1"
    Write-Host ""
    Write-Host "Target:"
    Write-Host "  $($State.Target)"
    Write-Host ""
    Write-Host "State:"
    Write-Host "  Image Stability V1.1 present: $($State.V11Installed)"
    if ($State.V11Installed) {
        Write-Host "  V1.1 marker found in:"
        foreach ($V11File in (Find-V11MarkerFiles)) {
            Write-Host "    $V11File"
        }
    }
    Write-Host "  Final image merge patched:    $($State.Patched)"
    Write-Host "  Backup manifest exists:       $($State.BackupExists)"
    Write-Host "  Current SHA256:               $($State.Sha256)"
    Write-Host ""

    if ($State.Patched -and $State.V11Installed) {
        Write-Host "STATUS: INSTALLED"
    }
    elseif ($State.Patched -and -not $State.V11Installed) {
        Write-Host "STATUS: WARNING - dedupe patch exists but V1.1 marker was not found"
    }
    else {
        Write-Host "STATUS: NOT INSTALLED"
    }
}

function Apply-Patch {
    $State = Get-State

    if (-not $State.V11Installed) {
        throw "Image Stability V1.1 marker was not found. Refusing to layer this patch. Nothing was changed."
    }

    if ($State.Patched) {
        Write-Host "Current-Turn Image Dedupe V1 is already installed."
        return
    }

    $Target = $State.Target
    $Text = [System.IO.File]::ReadAllText($Target)

    $Start = $Text.IndexOf($FunctionNeedle, [System.StringComparison]::Ordinal)
    if ($Start -lt 0) {
        throw "Could not find merge function start. Nothing was changed."
    }

    $End = $Text.IndexOf($NextAnchor, $Start, [System.StringComparison]::Ordinal)
    if ($End -lt 0) {
        throw "Could not find the expected next source anchor. Nothing was changed."
    }

    $OldBlock = $Text.Substring($Start, $End - $Start)

    # Strict source-shape checks before backing up or writing.
    $RequiredFragments = @(
        'const merged = entries.toSorted((left, right) => {',
        'const images = merged.flatMap((entry) => entry.image ? [entry.image] : []);',
        'imageOrder: merged.map((entry) => entry.imageOrder)'
    )

    foreach ($Fragment in $RequiredFragments) {
        if (-not $OldBlock.Contains($Fragment)) {
            throw "Unexpected merge-function source shape; missing: $Fragment`nNothing was changed."
        }
    }

    if ($OldBlock.Contains($Marker)) {
        throw "Patch marker unexpectedly exists inside source block. Nothing was changed."
    }

    # Detect the runtime file's newline convention.
    if ($Text.Contains("`r`n")) {
        $NL = "`r`n"
    }
    else {
        $NL = "`n"
    }

    $Lines = @(
        'function resolveMergedTurnImages(entries) {',
        '	if (entries.length === 0) return {};',
        '	const merged = entries.toSorted((left, right) => {',
        '		if (left.sourceIndex !== void 0 && right.sourceIndex !== void 0) return left.sourceIndex - right.sourceIndex || left.sequence - right.sequence;',
        '		if (left.sourceIndex !== void 0 || right.sourceIndex !== void 0) return left.sequence - right.sequence;',
        '		return left.sequence - right.sequence;',
        '	});',
        '	// FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1:',
        '	// Different upstream image paths can resolve the same current-turn image.',
        '	// Collapse only exact byte-identical image payloads at the final merge.',
        '	const deduped = [];',
        '	const seenImages = [];',
        '	for (const entry of merged) {',
        '		if (!entry.image) {',
        '			deduped.push(entry);',
        '			continue;',
        '		}',
        '		const duplicate = seenImages.some((image) => image.mimeType === entry.image.mimeType && image.data === entry.image.data);',
        '		if (duplicate) continue;',
        '		seenImages.push(entry.image);',
        '		deduped.push(entry);',
        '	}',
        '	const images = deduped.flatMap((entry) => entry.image ? [entry.image] : []);',
        '	return {',
        '		...images.length > 0 ? { images } : {},',
        '		imageOrder: deduped.map((entry) => entry.imageOrder)',
        '	};',
        '}',
        ''
    )

    $NewBlock = ($Lines -join $NL)

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    $BackupFile = Join-Path $BackupDir ([System.IO.Path]::GetFileName($Target) + ".original.js")

    if (-not (Test-Path $BackupFile)) {
        Copy-Item -LiteralPath $Target -Destination $BackupFile
    }

    $OriginalHash = Get-Sha256 $BackupFile

    # Refuse to use a stale backup from a different source build.
    if ($OriginalHash -ne $State.Sha256) {
        throw "Existing backup hash does not match the current unpatched runtime file. Refusing to overwrite or patch. Backup: $BackupFile"
    }

    $NewText = $Text.Substring(0, $Start) + $NewBlock + $Text.Substring($End)

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Target, $NewText, $Utf8NoBom)

    $Verify = [System.IO.File]::ReadAllText($Target)

    if (-not $Verify.Contains($Marker)) {
        Copy-Item -LiteralPath $BackupFile -Destination $Target -Force
        throw "Post-write marker verification failed. Original file was restored."
    }

    $FunctionCount = ([regex]::Matches($Verify, [regex]::Escape($FunctionNeedle))).Count
    if ($FunctionCount -ne 1) {
        Copy-Item -LiteralPath $BackupFile -Destination $Target -Force
        throw "Post-write function-count verification failed (count=$FunctionCount). Original file was restored."
    }

    $PatchedHash = Get-Sha256 $Target

    [ordered]@{
        patch = $Marker
        targetFile = $Target
        backupFile = $BackupFile
        originalSha256 = $OriginalHash
        patchedSha256 = $PatchedHash
        appliedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $Manifest -Encoding UTF8

    Write-Host ""
    Write-Host "CURRENT-TURN IMAGE DEDUPE V1 APPLY PASS"
    Write-Host ""
    Write-Host "Patched:"
    Write-Host "  $Target"
    Write-Host ""
    Write-Host "Original SHA256:"
    Write-Host "  $OriginalHash"
    Write-Host "Patched SHA256:"
    Write-Host "  $PatchedHash"
    Write-Host ""
    Write-Host "Backup:"
    Write-Host "  $BackupFile"
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
}

function Rollback-Patch {
    if (-not (Test-Path $Manifest)) {
        throw "Rollback manifest not found: $Manifest"
    }

    $Data = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json

    if (-not (Test-Path $Data.targetFile)) {
        throw "Target runtime file missing: $($Data.targetFile)"
    }

    if (-not (Test-Path $Data.backupFile)) {
        throw "Backup runtime file missing: $($Data.backupFile)"
    }

    $BackupHash = Get-Sha256 $Data.backupFile
    if ($BackupHash -ne $Data.originalSha256) {
        throw "Backup SHA256 does not match the manifest. Refusing rollback."
    }

    Copy-Item -LiteralPath $Data.backupFile -Destination $Data.targetFile -Force

    $RestoredHash = Get-Sha256 $Data.targetFile
    if ($RestoredHash -ne $Data.originalSha256) {
        throw "Rollback verification failed: restored SHA256 does not match original."
    }

    $RestoredText = [System.IO.File]::ReadAllText($Data.targetFile)
    if ($RestoredText.Contains($Marker)) {
        throw "Rollback verification failed: patch marker still present."
    }

    Write-Host ""
    Write-Host "CURRENT-TURN IMAGE DEDUPE V1 ROLLBACK PASS"
    Write-Host ""
    Write-Host "Restored:"
    Write-Host "  $($Data.targetFile)"
    Write-Host ""
    Write-Host "SHA256:"
    Write-Host "  $RestoredHash"
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
}

switch ($Action) {
    "status"   { Show-Status }
    "apply"    { Apply-Patch }
    "rollback" { Rollback-Patch }
}
