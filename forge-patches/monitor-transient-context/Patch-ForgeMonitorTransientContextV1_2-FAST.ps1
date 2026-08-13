param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Status","Apply","Rollback")]
    [string]$Mode = "Status"
)

$ErrorActionPreference = "Stop"

$PatchName = "Forge Monitor Transient Context V1.2 FAST"
$Marker = "FORGE_MONITOR_TRANSIENT_CONTEXT_V1"

$Root = Join-Path $env:APPDATA "npm\node_modules\openclaw"
$Dist = Join-Path $Root "dist"
$PatchDir = Join-Path $Root ".forge-patches\monitor-transient-context-v1"
$ManifestPath = Join-Path $PatchDir "manifest.json"
$BackupPath = Join-Path $PatchDir "run-attempt.pre-monitor-transient.bak"

function Get-OpenClawVersion {
    $packagePath = Join-Path $Root "package.json"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "OpenClaw package.json not found at $packagePath"
    }
    return [string]((Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json).version)
}

function Resolve-ContextHistoryBundlesFast {
    # The already-installed context-history patch left exactly two named backups.
    # Use those filenames to resolve the live bundles directly instead of scanning
    # every OpenClaw dist JS file with Select-String.
    $contextHistoryDir = Join-Path $Root ".forge-patches\context-history-v1"
    if (-not (Test-Path -LiteralPath $contextHistoryDir)) {
        throw "Fast resolver requires the existing context-history-v1 patch directory: $contextHistoryDir"
    }

    $backups = @(Get-ChildItem -LiteralPath $contextHistoryDir -File -Filter "*.bak")
    if ($backups.Count -ne 2) {
        throw "Expected exactly 2 context-history-v1 backup bundles; found $($backups.Count). Nothing changed."
    }

    $runCandidate = $null
    $threadCandidate = $null

    foreach ($backup in $backups) {
        $backupText = [System.IO.File]::ReadAllText($backup.FullName)

        if ($backupText.Contains('function prependCodexOpenClawPromptContext(prompt, context, options = {})')) {
            if ($null -ne $runCandidate) {
                throw "More than one run-attempt backup matched. Nothing changed."
            }
            $liveName = $backup.Name.Substring(0, $backup.Name.Length - 4)
            $runCandidate = Join-Path $Dist $liveName
        }

        if ($backupText.Contains('const CONTEXT_HEADER = "OpenClaw assembled context for this turn:";')) {
            if ($null -ne $threadCandidate) {
                throw "More than one thread-lifecycle backup matched. Nothing changed."
            }
            $liveName = $backup.Name.Substring(0, $backup.Name.Length - 4)
            $threadCandidate = Join-Path $Dist $liveName
        }
    }

    if ([string]::IsNullOrWhiteSpace($runCandidate) -or -not (Test-Path -LiteralPath $runCandidate)) {
        throw "Could not resolve the live run-attempt bundle from the existing context-history backup. Nothing changed."
    }
    if ([string]::IsNullOrWhiteSpace($threadCandidate) -or -not (Test-Path -LiteralPath $threadCandidate)) {
        throw "Could not resolve the live thread-lifecycle bundle from the existing context-history backup. Nothing changed."
    }

    return [pscustomobject]@{
        RunFile = [string]$runCandidate
        ThreadFile = [string]$threadCandidate
    }
}

function Count-Occurrences {
    param(
        [string]$Text,
        [string]$Needle
    )

    if ([string]::IsNullOrEmpty($Needle)) { return 0 }

    $count = 0
    $offset = 0
    while ($true) {
        $index = $Text.IndexOf($Needle, $offset, [System.StringComparison]::Ordinal)
        if ($index -lt 0) { break }
        $count++
        $offset = $index + $Needle.Length
    }
    return $count
}

function Get-Newline {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
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

$version = Get-OpenClawVersion
if ($version -ne "2026.7.1") {
    throw "This patch is pinned to OpenClaw 2026.7.1. Found $version. Nothing changed."
}

$resolvedBundles = Resolve-ContextHistoryBundlesFast
$RunFile = [string]$resolvedBundles.RunFile
$ThreadFile = [string]$resolvedBundles.ThreadFile

$runText = [System.IO.File]::ReadAllText($RunFile)
$threadText = [System.IO.File]::ReadAllText($ThreadFile)

# This patch deliberately layers on top of the already-proven context-history carrier.
# If these exact seams are absent, refuse rather than guessing against a locally modified bundle.
$TurnAnchor = 'const turnStartParams = buildTurnStartParams(params, {'
$PromptOld = 'promptText: forgeContextHistoryCarrier?.promptText ?? codexTurnPromptText,'
$AdditionalOld = 'additionalContext: forgeContextHistoryCarrier?.additionalContext, /* FORGE_CONTEXT_HISTORY_V1 */'
$ThreadAdditional = '...(options.additionalContext ? { additionalContext: options.additionalContext } : {}), /* FORGE_CONTEXT_HISTORY_V1 */'

$markerCount = Count-Occurrences $runText $Marker
$turnCount = Count-Occurrences $runText $TurnAnchor
$promptCount = Count-Occurrences $runText $PromptOld
$additionalCount = Count-Occurrences $runText $AdditionalOld
$threadAdditionalCount = Count-Occurrences $threadText $ThreadAdditional

function Show-Status {
    Write-Host ""
    Write-Host $PatchName
    Write-Host ("=" * $PatchName.Length)
    Write-Host "OpenClaw version : $version"
    Write-Host "Run bundle       : $RunFile"
    Write-Host "Thread bundle    : $ThreadFile"
    Write-Host "Run SHA256       : $(Get-Sha256 $RunFile)"
    Write-Host "Patch marker     : $markerCount"
    Write-Host ""
    Write-Host "Required existing seams:"
    Write-Host "  turnStart anchor                : $turnCount"
    Write-Host "  context-history prompt seam     : $promptCount"
    Write-Host "  context-history additional seam : $additionalCount"
    Write-Host "  thread additionalContext seam   : $threadAdditionalCount"
    Write-Host ""
    if ($markerCount -gt 0) {
        Write-Host "State: PATCHED"
    } elseif ($turnCount -eq 1 -and $promptCount -eq 1 -and $additionalCount -eq 1 -and $threadAdditionalCount -eq 1) {
        Write-Host "State: READY"
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
        throw "Current run bundle hash differs from the recorded patched hash. Refusing rollback so newer local patches are not overwritten."
    }

    Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $restoredHash = Get-Sha256 $RunFile
    $expectedOriginal = ([string]$manifest.originalSha256).ToLowerInvariant()
    if ($restoredHash -ne $expectedOriginal) {
        throw "Rollback copy completed, but restored hash does not match the recorded pre-patch hash."
    }

    Write-Host ""
    Write-Host "ROLLBACK PASS"
    Write-Host "Restored the immediate pre-$PatchName run bundle."
    Write-Host "SHA256: $restoredHash"
    Write-Host "Restart the OpenClaw gateway before testing the restored runtime."
    Write-Host ""
    exit 0
}

# APPLY
if ($markerCount -gt 0) {
    throw "$Marker is already present. Nothing changed."
}
if ($turnCount -ne 1) {
    throw "Preflight failed: expected exactly one turnStart anchor, found $turnCount. Nothing changed."
}
if ($promptCount -ne 1) {
    throw "Preflight failed: expected exactly one context-history prompt seam, found $promptCount. Nothing changed."
}
if ($additionalCount -ne 1) {
    throw "Preflight failed: expected exactly one context-history additionalContext seam, found $additionalCount. Nothing changed."
}
if ($threadAdditionalCount -ne 1) {
    throw "Preflight failed: the existing thread additionalContext bridge was not found exactly once. Nothing changed."
}

$originalHash = Get-Sha256 $RunFile
$nl = Get-Newline $runText

# The monitor currently uses before_prompt_build.prependContext, so its review scaffolding
# becomes part of the ordinary user-facing prompt. For Codex app-server only, detach exactly
# that monitor-owned prefix from the durable user prompt and preserve it as untrusted
# turn/start.additionalContext for the current inference.
#
# We split at OpenClaw's normal Discord "Conversation info" marker. That leaves the normal
# Discord prompt (metadata + real inbound message) untouched and only detaches the monitor's
# own preamble / previous-message review context.
$CarrierLines = @(
'    /* FORGE_MONITOR_TRANSIENT_CONTEXT_V1: keep Forge monitor review context model-visible without ordinary native user-history persistence. */',
'    const forgeMonitorTransientContextCarrier = (() => {',
'        const source = forgeContextHistoryCarrier?.promptText ?? codexTurnPromptText;',
'        const monitorHeader = "[Forge Discord Monitor —";',
'        const normalPromptMarker = "Conversation info (untrusted metadata):";',
'        const monitorIndex = source.indexOf(monitorHeader);',
'        const normalPromptIndex = monitorIndex >= 0',
'            ? source.indexOf(normalPromptMarker, monitorIndex + monitorHeader.length)',
'            : -1;',
'        if (monitorIndex < 0 || normalPromptIndex < 0) return;',
'        const monitorText = source.slice(monitorIndex, normalPromptIndex).trim();',
'        if (!monitorText) return;',
'        const prefixText = source.slice(0, monitorIndex).trimEnd();',
'        const normalPromptText = source.slice(normalPromptIndex).trimStart();',
'        const cleanedPromptText = [prefixText, normalPromptText].filter(Boolean).join("\n\n");',
'        const additionalContext = {',
'            ...(forgeContextHistoryCarrier?.additionalContext ?? {}),',
'            forge_discord_monitor_review_context: {',
'                kind: "untrusted",',
'                value: monitorText',
'            }',
'        };',
'        embeddedAgentLog.info("forge discord monitor review context routed through additionalContext", {',
'            sessionId: params.sessionId,',
'            contextChars: monitorText.length,',
'            persistedPromptCharsBefore: source.length,',
'            persistedPromptCharsAfter: cleanedPromptText.length',
'        });',
'        return {',
'            promptText: cleanedPromptText,',
'            additionalContext',
'        };',
'    })();'
)

$CarrierBlock = ($CarrierLines -join $nl) + $nl + '    ' + $TurnAnchor
$patched = $runText.Replace($TurnAnchor, $CarrierBlock)

$PromptNew = 'promptText: forgeMonitorTransientContextCarrier?.promptText ?? forgeContextHistoryCarrier?.promptText ?? codexTurnPromptText,'
$AdditionalNew = 'additionalContext: forgeMonitorTransientContextCarrier?.additionalContext ?? forgeContextHistoryCarrier?.additionalContext, /* FORGE_CONTEXT_HISTORY_V1 */'

$patched = $patched.Replace($PromptOld, $PromptNew)
$patched = $patched.Replace($AdditionalOld, $AdditionalNew)

# Validate the in-memory mutation before touching disk.
if ((Count-Occurrences $patched $Marker) -ne 1) {
    throw "Patch validation failed: marker count is not 1. Nothing changed."
}
if ((Count-Occurrences $patched 'forgeMonitorTransientContextCarrier?.promptText') -ne 1) {
    throw "Patch validation failed: patched prompt seam count is not 1. Nothing changed."
}
if ((Count-Occurrences $patched 'forgeMonitorTransientContextCarrier?.additionalContext') -ne 1) {
    throw "Patch validation failed: patched additionalContext seam count is not 1. Nothing changed."
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null

# Always back up the exact immediate pre-this-patch bundle. This intentionally preserves
# every earlier local Forge/OpenClaw patch that is already installed.
Copy-Item -LiteralPath $RunFile -Destination $BackupPath -Force

$temp = "$RunFile.$Marker.tmp.js"
try {
    [System.IO.File]::WriteAllText($temp, $patched, [System.Text.UTF8Encoding]::new($false))
    Assert-NodeSyntax $temp
    Move-Item -LiteralPath $temp -Destination $RunFile -Force
    Assert-NodeSyntax $RunFile

    $patchedHash = Get-Sha256 $RunFile

    $manifest = [ordered]@{
        patch = $PatchName
        marker = $Marker
        openClawVersion = $version
        target = $RunFile
        originalSha256 = $originalHash
        patchedSha256 = $patchedHash
        appliedAt = (Get-Date).ToString("o")
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "APPLY PASS"
    Write-Host "Patch:  $PatchName"
    Write-Host "Target: $RunFile"
    Write-Host ""
    Write-Host "Behavior:"
    Write-Host "  - Forge still receives the full monitor review context on the current inference."
    Write-Host "  - Monitor review scaffolding is carried as Codex untrusted additionalContext."
    Write-Host "  - The ordinary durable native user prompt keeps the normal Discord prompt + real inbound message."
    Write-Host "  - Non-monitor turns are unchanged."
    Write-Host "  - Canonical OpenClaw transcript/config were not modified by this patch."
    Write-Host ""
    Write-Host "SHA256:"
    Write-Host "  before: $originalHash"
    Write-Host "  after : $patchedHash"
    Write-Host ""
    Write-Host "Backup:   $BackupPath"
    Write-Host "Manifest: $ManifestPath"
    Write-Host ""
    Write-Host "Restart the OpenClaw gateway before testing."
    Write-Host ""
} catch {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    # If the target changed before manifest completion, restore the immediate backup.
    if (Test-Path -LiteralPath $BackupPath) {
        Copy-Item -LiteralPath $BackupPath -Destination $RunFile -Force
    }
    throw
}
