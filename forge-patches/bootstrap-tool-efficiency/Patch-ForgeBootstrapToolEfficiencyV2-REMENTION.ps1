param(
    [switch]$Apply,
    [switch]$Undo
)

$ErrorActionPreference = "Stop"

$ExpectedVersion = "2026.7.1"
$Target = Join-Path $env:APPDATA "npm\node_modules\openclaw\dist\system-prompt-config-BeuaroSf.js"
$PatchDir = Join-Path $HOME ".openclaw\.forge-patches\bootstrap-tool-efficiency-v2"
$Backup = Join-Path $PatchDir "system-prompt-config-v1.js"

$Old = 'Scan <available_skills>. If one clearly applies, use its instructions. If that skill''s SKILL.md instructions are already present in the active context, reuse them rather than reading the file again. Otherwise read its SKILL.md at exact <location> with \`${params.readToolName}\`, then follow it. If a tool call fails in a way that may indicate stale or incorrect usage instructions, re-read the relevant SKILL.md before retrying. Do not retry a tool that has already reported a persistent configuration, permission, disabled, or unavailable error while that same condition remains known in the active context, unless the user explicitly asks or there is evidence the condition changed. Do not repeat the same informational tool call when a usable result for the same effective request is already present in the active context, unless the underlying state may have changed, the earlier result was incomplete, or a retry is otherwise necessary.'

$New = 'Scan <available_skills>. If one clearly applies, use its instructions. For native skill carry-over purposes, treat any applicable skill whose SKILL.md instructions are already present in the active context as re-mentioned for the current turn. Reuse those instructions without reading the file again. Otherwise read its SKILL.md at exact <location> with \`${params.readToolName}\`, then follow it. If a tool call fails in a way that may indicate stale or incorrect usage instructions, re-read the relevant SKILL.md before retrying. Do not retry a tool that has already reported a persistent configuration, permission, disabled, or unavailable error while that same condition remains known in the active context, unless the user explicitly asks or there is evidence the condition changed. Do not repeat the same informational tool call when a usable result for the same effective request is already present in the active context, unless the underlying state may have changed, the earlier result was incomplete, or a retry is otherwise necessary.'

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Count-Literal([string]$Text, [string]$Needle) {
    $Count = 0
    $Start = 0
    while (($Index = $Text.IndexOf($Needle, $Start, [System.StringComparison]::Ordinal)) -ge 0) {
        $Count++
        $Start = $Index + $Needle.Length
    }
    return $Count
}

$Version = (& openclaw --version 2>$null | Out-String).Trim()
if ($Version -notmatch [regex]::Escape($ExpectedVersion)) {
    throw "Expected OpenClaw $ExpectedVersion, got: $Version"
}

if (-not (Test-Path -LiteralPath $Target)) {
    throw "Target not found: $Target"
}

Write-Host "OpenClaw: $Version"
Write-Host "Target:   $Target"
Write-Host "SHA256:   $(Get-Sha256 $Target)"
Write-Host ""

if ($Undo) {
    if (-not (Test-Path -LiteralPath $Backup)) {
        throw "V1 backup not found: $Backup"
    }

    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    Write-Host "V2 UNDONE."
    Write-Host "Restored V1: $Backup"
    Write-Host "SHA256:      $(Get-Sha256 $Target)"
    exit 0
}

$Text = [System.IO.File]::ReadAllText($Target)
$OldCount = Count-Literal $Text $Old
$NewCount = Count-Literal $Text $New

if (-not $Apply) {
    Write-Host "DRY CHECK ONLY - no files changed."
    Write-Host "V1 prompt matches: $OldCount"
    Write-Host "V2 prompt matches: $NewCount"
    Write-Host ""

    if ($OldCount -eq 1 -and $NewCount -eq 0) {
        Write-Host "READY TO APPLY V2."
    }
    elseif ($OldCount -eq 0 -and $NewCount -eq 1) {
        Write-Host "V2 ALREADY PRESENT."
    }
    else {
        throw "Unexpected prompt state. Refusing to patch."
    }
    exit 0
}

if ($OldCount -ne 1 -or $NewCount -ne 0) {
    throw "Expected exactly one V1 prompt and zero V2 prompts. Found V1=$OldCount V2=$NewCount. Refusing to patch."
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $Backup)) {
    Copy-Item -LiteralPath $Target -Destination $Backup
}
else {
    $BackupText = [System.IO.File]::ReadAllText($Backup)
    if ((Count-Literal $BackupText $Old) -ne 1) {
        throw "Existing V1 backup is not the expected V1 runtime file. Refusing to continue."
    }
}

$Patched = $Text.Replace($Old, $New)
[System.IO.File]::WriteAllText($Target, $Patched, [System.Text.UTF8Encoding]::new($false))

$Verify = [System.IO.File]::ReadAllText($Target)
if ((Count-Literal $Verify $Old) -ne 0 -or (Count-Literal $Verify $New) -ne 1) {
    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    throw "Verification failed. V1 runtime restored."
}

Write-Host "V2 PATCH APPLIED."
Write-Host "V1 backup: $Backup"
Write-Host "New SHA:   $(Get-Sha256 $Target)"
Write-Host ""
Write-Host "Then refresh Forge's backend prompt with:"
Write-Host "  /reset soft"
