param(
    [switch]$Apply,
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'

$Target   = Join-Path $HOME '.openclaw\workspace\AGENTS.md'
$PatchDir = Join-Path $HOME '.openclaw\.forge-patches\kb-retrieval-efficiency-v1'
$Backup   = Join-Path $PatchDir 'AGENTS-original.md'

$Rule1 = '- Start with the single routed KB file for the question and a focused search. Retrieve only the relevant passage (normally no more than about 20 lines). Never read an entire KB file into context for a normal lookup.'
$Rule2 = '- Consult additional KB files or expand the passage only if the first bounded result is insufficient to answer safely.'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

if (-not (Test-Path -LiteralPath $Target)) {
    throw "AGENTS.md not found: $Target"
}

if ($Undo) {
    if (-not (Test-Path -LiteralPath $Backup)) {
        throw "Backup not found: $Backup"
    }

    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    Write-Host "UNDO COMPLETE"
    Write-Host "Restored: $Target"
    Write-Host "SHA256:  $(Get-Sha256 $Target)"
    exit 0
}

$Text = [System.IO.File]::ReadAllText($Target)
$NL = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($Text.Contains($Rule1) -and $Text.Contains($Rule2)) {
    Write-Host "ALREADY PATCHED"
    Write-Host "Target: $Target"
    Write-Host "SHA256: $(Get-Sha256 $Target)"
    exit 0
}

$Pattern = 'Procedure:\r?\n- Consult the relevant KB file\(s\) before answering\.'
$Matches = [regex]::Matches($Text, $Pattern)

if ($Matches.Count -ne 1) {
    throw "Expected exactly one Support KB Procedure anchor; found $($Matches.Count). No changes made."
}

$Replacement = "Procedure:${NL}- Consult the relevant KB file(s) before answering.${NL}${Rule1}${NL}${Rule2}"
$NewText = [regex]::Replace($Text, $Pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Replacement }, 1)

Write-Host "TARGET"
Write-Host "  $Target"
Write-Host ""
Write-Host "CURRENT SHA256"
Write-Host "  $(Get-Sha256 $Target)"
Write-Host ""
Write-Host "INSERT AFTER: - Consult the relevant KB file(s) before answering."
Write-Host "  $Rule1"
Write-Host "  $Rule2"
Write-Host ""

if (-not $Apply) {
    Write-Host "DRY RUN ONLY - NO FILES CHANGED"
    Write-Host ""
    Write-Host "To apply:"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Apply"
    exit 0
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $Backup)) {
    Copy-Item -LiteralPath $Target -Destination $Backup
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Target, $NewText, $Utf8NoBom)

Write-Host "APPLY COMPLETE"
Write-Host "Backup: $Backup"
Write-Host "New SHA256: $(Get-Sha256 $Target)"
Write-Host ""
Write-Host "Undo:"
Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Undo"
