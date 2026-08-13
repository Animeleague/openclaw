param(
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$Target = Join-Path $Dist "thread-lifecycle-qWE88Dn2.js"

$PatchId = "FORGE_CODEX_TRANSIENT_LUNA_V1"
$RequiredBaselineMarker = "FORGE_CODEX_STABLE_TOOL_CATALOG_V2"

$StateDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-transient-luna-v1"
$Backup = Join-Path $StateDir "thread-lifecycle.original.js"
$Manifest = Join-Path $StateDir "manifest.json"

function Assert-Target {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "Required OpenClaw Codex target not found: $Target"
    }
}

function Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Node-Check([string]$Path) {
    & node --check $Path
    if ($LASTEXITCODE -ne 0) {
        throw "node --check failed: $Path"
    }
}

function Get-Newline([string]$Text) {
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Join-Lines([string[]]$Lines, [string]$NL) {
    return ($Lines -join $NL)
}

function Get-SourceBlocks([string]$Text) {
    $NL = Get-Newline $Text

    $OldRotation = Join-Lines @(
        "`t`tif (binding?.threadId && shouldRotateCodexGpt56MultiAgentBinding({",
        "`t`t`tbindingModel: binding.model,",
        "`t`t`trequestedModel: params.params.modelId",
        "`t`t})) {",
        "`t`t`tembeddedAgentLog.debug(`"codex app-server GPT-5.6 multi-agent version changed; starting a new thread`", {",
        "`t`t`t`tthreadId: binding.threadId,",
        "`t`t`t`tbindingModel: binding.model,",
        "`t`t`t`trequestedModel: params.params.modelId",
        "`t`t`t});",
        "`t`t`tawait clearCurrentBinding(`"rotating a GPT-5.6 multi-agent thread binding`");",
        "`t`t`tbinding = void 0;",
        "`t`t}"
    ) $NL

    $NewRotation = Join-Lines @(
        "`t`tlet forgeTransientLunaModelSwitchV1 = false; // $PatchId",
        "`t`tif (binding?.threadId && shouldRotateCodexGpt56MultiAgentBinding({",
        "`t`t`tbindingModel: binding.model,",
        "`t`t`trequestedModel: params.params.modelId",
        "`t`t})) {",
        "`t`t`tconst forgeBindingModelV1 = (binding.model ?? `"`").trim().toLowerCase().split(`"/`").at(-1);",
        "`t`t`tconst forgeRequestedModelV1 = (params.params.modelId ?? `"`").trim().toLowerCase().split(`"/`").at(-1);",
        "`t`t`tconst forgeSolToLunaV1 = (forgeBindingModelV1 === `"gpt-5.6-sol`" || forgeBindingModelV1 === `"gpt-5.6-terra`") && forgeRequestedModelV1 === `"gpt-5.6-luna`";",
        "`t`t`tif (forgeSolToLunaV1) {",
        "`t`t`t`tembeddedAgentLog.debug(`"codex app-server GPT-5.6 Sol/Terra -> Luna switch; starting transient Luna thread and preserving durable binding`", {",
        "`t`t`t`t`tthreadId: binding.threadId,",
        "`t`t`t`t`tbindingModel: binding.model,",
        "`t`t`t`t`trequestedModel: params.params.modelId",
        "`t`t`t`t});",
        "`t`t`t`tforgeTransientLunaModelSwitchV1 = true;",
        "`t`t`t`tbinding = void 0;",
        "`t`t`t} else {",
        "`t`t`t`tembeddedAgentLog.debug(`"codex app-server GPT-5.6 multi-agent version changed; starting a new thread`", {",
        "`t`t`t`t`tthreadId: binding.threadId,",
        "`t`t`t`t`tbindingModel: binding.model,",
        "`t`t`t`t`trequestedModel: params.params.modelId",
        "`t`t`t`t});",
        "`t`t`t`tawait clearCurrentBinding(`"rotating a GPT-5.6 multi-agent thread binding`");",
        "`t`t`t`tbinding = void 0;",
        "`t`t`t}",
        "`t`t}"
    ) $NL

    $OldPreserve = "`t`tlet preserveExistingBinding = params.nativeProviderWebSearchSupport === `"unknown`" && !binding?.threadId;"
    $NewPreserve = "`t`tlet preserveExistingBinding = forgeTransientLunaModelSwitchV1 || params.nativeProviderWebSearchSupport === `"unknown`" && !binding?.threadId;"

    [pscustomobject]@{
        NL = $NL
        OldRotation = $OldRotation
        NewRotation = $NewRotation
        OldPreserve = $OldPreserve
        NewPreserve = $NewPreserve
    }
}

function Show-Status {
    Assert-Target
    $Text = [System.IO.File]::ReadAllText($Target)
    $Blocks = Get-SourceBlocks $Text

    $Marker = $Text.Contains($PatchId)
    $Preserve = $Text.Contains($Blocks.NewPreserve)
    $Baseline = $Text.Contains($RequiredBaselineMarker)
    $NativeRotation = $Text.Contains($Blocks.OldRotation)

    Write-Host ""
    Write-Host "Forge Codex Transient Luna V1"
    Write-Host ""
    Write-Host "Target:"
    Write-Host "  $Target"
    Write-Host ""
    Write-Host "State:"
    Write-Host "  Stable Tool Catalogue V2 present: $Baseline"
    Write-Host "  Transient Luna marker present:    $Marker"
    Write-Host "  Preserve-binding hook present:    $Preserve"
    Write-Host "  Native rotation block unpatched:  $NativeRotation"
    Write-Host "  Backup manifest exists:           $(Test-Path -LiteralPath $Manifest)"
    Write-Host "  Current SHA256:                   $(Sha $Target)"
    Write-Host ""

    if ($Marker -and $Preserve -and -not $NativeRotation) {
        Write-Host "STATUS: INSTALLED"
    }
    elseif (-not $Marker -and -not $Preserve -and $NativeRotation) {
        Write-Host "STATUS: NOT INSTALLED"
    }
    else {
        Write-Host "STATUS: PARTIAL / UNEXPECTED - do not restart until inspected"
    }
}

function Apply-Patch {
    Assert-Target

    $Text = [System.IO.File]::ReadAllText($Target)
    $Blocks = Get-SourceBlocks $Text

    if ($Text.Contains($PatchId)) {
        Write-Host "Transient Luna V1 already appears installed; no changes made."
        Show-Status
        return
    }

    if (-not $Text.Contains($RequiredBaselineMarker)) {
        throw "Required known-good baseline '$RequiredBaselineMarker' is not present. Refusing to patch."
    }

    $RotationCount = ([regex]::Matches($Text, [regex]::Escape($Blocks.OldRotation))).Count
    $PreserveCount = ([regex]::Matches($Text, [regex]::Escape($Blocks.OldPreserve))).Count

    if ($RotationCount -ne 1) {
        throw "Preflight failed: native GPT-5.6 rotation block occurred $RotationCount times; expected 1. Nothing was modified."
    }
    if ($PreserveCount -ne 1) {
        throw "Preflight failed: preserveExistingBinding anchor occurred $PreserveCount times; expected 1. Nothing was modified."
    }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    $OriginalSha = Sha $Target
    if (-not (Test-Path -LiteralPath $Backup)) {
        Copy-Item -LiteralPath $Target -Destination $Backup -Force
    } else {
        $ExistingBackupSha = Sha $Backup
        if ($ExistingBackupSha -ne $OriginalSha -and -not (Test-Path -LiteralPath $Manifest)) {
            throw "Backup file already exists but does not match the current target. Refusing to overwrite it."
        }
    }

    $Patched = $Text.Replace($Blocks.OldRotation, $Blocks.NewRotation)
    $Patched = $Patched.Replace($Blocks.OldPreserve, $Blocks.NewPreserve)

    Write-NoBom $Target $Patched

    try {
        Node-Check $Target

        $Verify = [System.IO.File]::ReadAllText($Target)
        $VerifyBlocks = Get-SourceBlocks $Verify

        if (-not $Verify.Contains($PatchId)) {
            throw "Verification failed: patch marker missing."
        }
        if (-not $Verify.Contains($VerifyBlocks.NewPreserve)) {
            throw "Verification failed: preserve-binding hook missing."
        }
        if ($Verify.Contains($VerifyBlocks.OldRotation)) {
            throw "Verification failed: original rotation block still present."
        }

        $PatchedSha = Sha $Target
        $ManifestData = [ordered]@{
            patchId = $PatchId
            targetFile = $Target
            backupFile = $Backup
            originalSha256 = $OriginalSha
            patchedSha256 = $PatchedSha
            appliedAt = (Get-Date).ToString("o")
        }
        $ManifestData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding UTF8

        Write-Host ""
        Write-Host "TRANSIENT LUNA V1 APPLY PASS"
        Write-Host ""
        Write-Host "Behavior:"
        Write-Host "  Sol/Terra durable binding -> Luna: transient Luna thread; durable binding preserved"
        Write-Host "  Luna durable binding -> Sol/Terra: native rotation unchanged"
        Write-Host "  Same-model turns: unchanged"
        Write-Host ""
        Write-Host "Original SHA256:"
        Write-Host "  $OriginalSha"
        Write-Host "Patched SHA256:"
        Write-Host "  $PatchedSha"
        Write-Host ""
        Write-Host "Restart once:"
        Write-Host "  openclaw gateway restart"
        Write-Host ""
    }
    catch {
        Copy-Item -LiteralPath $Backup -Destination $Target -Force
        throw
    }
}

function Rollback-Patch {
    Assert-Target

    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        throw "Rollback manifest not found: $Manifest"
    }
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
        throw "Rollback backup not found: $Backup"
    }

    $M = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ([string]$M.patchId -ne $PatchId) {
        throw "Rollback manifest patch id mismatch."
    }

    $CurrentSha = Sha $Target
    if ([string]$M.patchedSha256 -and $CurrentSha -ne [string]$M.patchedSha256) {
        throw "Target changed after this patch was applied. Refusing to overwrite newer edits."
    }

    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    Node-Check $Target

    $RestoredSha = Sha $Target
    if ($RestoredSha -ne [string]$M.originalSha256) {
        throw "Rollback verification failed: restored SHA256 does not match original."
    }

    $Restored = [System.IO.File]::ReadAllText($Target)
    if ($Restored.Contains($PatchId)) {
        throw "Rollback verification failed: patch marker still present."
    }

    Write-Host ""
    Write-Host "TRANSIENT LUNA V1 ROLLBACK PASS"
    Write-Host ""
    Write-Host "Restored SHA256:"
    Write-Host "  $RestoredSha"
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
