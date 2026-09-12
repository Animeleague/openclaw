# Forge Codex Sol/Luna Continuity + Temporary 120K Cap
# Live-proven 2026-09-12
# Canon markers:
#   FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1
#   FORGE_CODEX_LUNA_NEVER_DURABLE_V1
#
# Assumes the existing live prerequisites:
#   FORGE_CODEX_TRANSIENT_LUNA_V1
#   FORGE_CODEX_DUAL_WARM_THREADS_V2_1
#   FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4
#   FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3
#
# This script is intentionally fail-closed: if expected live anchors drift,
# it restores backups rather than guessing.

& {
    $ErrorActionPreference = "Stop"

    $projectDist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"

    if (-not (Test-Path -LiteralPath $projectDist)) {
        throw "Active Codex project dist not found: $projectDist"
    }

    $lifecycle = @(
        rg -l --glob "thread-lifecycle-*.js" "FORGE_CODEX_DUAL_WARM_THREADS_V2_1" $projectDist 2>$null
    ) | Select-Object -First 1

    $runAttempt = @(
        rg -l --glob "run-attempt-*.js" "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3" $projectDist 2>$null
    ) | Select-Object -First 1

    if (-not $lifecycle) {
        throw "Could not locate active thread-lifecycle bundle."
    }

    if (-not $runAttempt) {
        throw "Could not locate active run-attempt bundle."
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $lifecycleBackup = "$lifecycle.pre-sol-luna-continuity-$stamp"
    $runAttemptBackup = "$runAttempt.pre-sol-luna-continuity-$stamp"

    function Count-Literal([string]$Text, [string]$Needle) {
        if ([string]::IsNullOrEmpty($Needle)) { return 0 }
        return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    }

    function Write-NoBom([string]$Path, [string]$Text) {
        [System.IO.File]::WriteAllText(
            $Path,
            $Text,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }

    Copy-Item -LiteralPath $lifecycle -Destination $lifecycleBackup -Force
    Copy-Item -LiteralPath $runAttempt -Destination $runAttemptBackup -Force

    try {
        $L = [System.IO.File]::ReadAllText($lifecycle)
        $R = [System.IO.File]::ReadAllText($runAttempt)

        foreach ($required in @(
            "FORGE_CODEX_TRANSIENT_LUNA_V1",
            "FORGE_CODEX_DUAL_WARM_THREADS_V2_1"
        )) {
            if (-not $L.Contains($required)) {
                throw "Required lifecycle prerequisite missing: $required"
            }
        }

        foreach ($required in @(
            "FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4",
            "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3"
        )) {
            if (-not $R.Contains($required)) {
                throw "Required run-attempt prerequisite missing: $required"
            }
        }

        $nlL = if ($L.Contains("`r`n")) { "`r`n" } else { "`n" }

        # ------------------------------------------------------------------
        # 1. Monitor Warm must not undo Dual Warm isolation.
        # ------------------------------------------------------------------

        $monitorMarker = "FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1"

        if (-not $L.Contains($monitorMarker)) {
            $monitorStart = $L.IndexOf("if (forgeMonitorWarmRunV104) {")

            if ($monitorStart -lt 0) {
                throw "Could not find forgeMonitorWarmRunV104 block."
            }

            $monitorEnd = $L.IndexOf(
                "if (forgeDisposableRunV1) {",
                $monitorStart
            )

            if ($monitorEnd -lt 0) {
                throw "Could not find forgeDisposableRunV1 anchor."
            }

            $oldMonitorBlock = $L.Substring(
                $monitorStart,
                $monitorEnd - $monitorStart
            )

            if (
                -not $oldMonitorBlock.Contains("forgeLunaSidecarActiveV2 = false") -or
                -not $oldMonitorBlock.Contains("forgeTransientLunaModelSwitchV1 = false")
            ) {
                throw "Monitor block no longer matches proven regression shape."
            }

            $newMonitorBlock = @(
                'if (forgeMonitorWarmRunV104) {'
                '    // FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1'
                '    // Monitor rollback must not undo Dual Warm model isolation.'
                '    if (!forgeLunaSidecarActiveV2 && !forgeTransientLunaModelSwitchV1) {'
                '        binding = await params.bindingStore.read(bindingIdentity);'
                '    }'
                '    preserveExistingBinding = forgeTransientLunaModelSwitchV1 || params.nativeProviderWebSearchSupport === "unknown" && !binding?.threadId;'
                '}'
                ''
            ) -join $nlL

            $L =
                $L.Substring(0, $monitorStart) +
                $newMonitorBlock +
                $L.Substring($monitorEnd)
        }

        # ------------------------------------------------------------------
        # 2. Luna must never claim the durable principal binding.
        # ------------------------------------------------------------------

        $lunaMarker = "FORGE_CODEX_LUNA_NEVER_DURABLE_V1"

        if (-not $L.Contains($lunaMarker)) {
            $anchor = 'let forgeTransientLunaModelSwitchV1 = false; // FORGE_CODEX_TRANSIENT_LUNA_V1'

            if ((Count-Literal $L $anchor) -ne 1) {
                throw "Transient Luna declaration anchor did not occur exactly once."
            }

            $insert = @(
                ''
                '           // FORGE_CODEX_LUNA_NEVER_DURABLE_V1'
                '           const forgeRequestedModelNeverDurableV1 = (params.params.modelId ?? "").trim().toLowerCase().split("/").at(-1);'
                '           if (!binding?.threadId && forgeRequestedModelNeverDurableV1 === "gpt-5.6-luna") {'
                '                   const forgeExistingLunaSidecarNeverDurableV1 = forgeLunaSidecarsV2.get(forgeLunaSidecarKeyV2);'
                '                   forgeLunaSidecarActiveV2 = true;'
                '                   forgeTransientLunaModelSwitchV1 = true;'
                '                   if (forgeExistingLunaSidecarNeverDurableV1?.threadId) {'
                '                           binding = forgeExistingLunaSidecarNeverDurableV1;'
                '                   }'
                '           }'
            ) -join $nlL

            $L = $L.Replace($anchor, $anchor + $insert)
        }

        # ------------------------------------------------------------------
        # 3. Temporarily raise completed-turn clean rollover cap 60k -> 120k.
        # ------------------------------------------------------------------

        $oldThreshold = 'forgePostTurnNativeTokensV3 >= 60_000'
        $newThreshold = 'forgePostTurnNativeTokensV3 >= 120_000'

        $oldLog = '"forge native thread reached completed-turn 60k hardcap; fresh rollover armed"'
        $newLog = '"forge native thread reached completed-turn 120k hardcap; fresh rollover armed"'

        $oldHardcap = 'hardcap: 60_000'
        $newHardcap = 'hardcap: 120_000'

        if ($R.Contains($oldThreshold)) {
            if ((Count-Literal $R $oldThreshold) -ne 1) {
                throw "60k threshold occurred more than once."
            }

            $R = $R.Replace($oldThreshold, $newThreshold)
            $R = $R.Replace($oldLog, $newLog)
            $R = $R.Replace($oldHardcap, $newHardcap)
        }
        elseif (-not $R.Contains($newThreshold)) {
            throw "Neither expected 60k nor 120k native hardcap found."
        }

        Write-NoBom $lifecycle $L
        Write-NoBom $runAttempt $R

        & node --check $lifecycle
        if ($LASTEXITCODE -ne 0) {
            throw "Lifecycle node --check failed."
        }

        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Run-attempt node --check failed."
        }

        $VL = [System.IO.File]::ReadAllText($lifecycle)
        $VR = [System.IO.File]::ReadAllText($runAttempt)

        foreach ($marker in @(
            "FORGE_CODEX_MONITOR_DUAL_WARM_INTERLOCK_V1",
            "FORGE_CODEX_LUNA_NEVER_DURABLE_V1",
            "FORGE_CODEX_DUAL_WARM_THREADS_V2_1"
        )) {
            if (-not $VL.Contains($marker)) {
                throw "Lifecycle validation marker missing: $marker"
            }
        }

        foreach ($marker in @(
            "FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4",
            "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3",
            "forgePostTurnNativeTokensV3 >= 120_000"
        )) {
            if (-not $VR.Contains($marker)) {
                throw "Run-attempt validation marker missing: $marker"
            }
        }

        Write-Host ""
        Write-Host "PASS - Forge Sol/Luna continuity live canon installed." -ForegroundColor Green
        Write-Host "Lifecycle: $lifecycle"
        Write-Host "Run attempt: $runAttempt"
        Write-Host "Temporary clean rollover cap: 120k"
        Write-Host ""
        Write-Host "Lifecycle SHA256:"
        (Get-FileHash -LiteralPath $lifecycle -Algorithm SHA256).Hash
        Write-Host "Run-attempt SHA256:"
        (Get-FileHash -LiteralPath $runAttempt -Algorithm SHA256).Hash
    }
    catch {
        Copy-Item -LiteralPath $lifecycleBackup -Destination $lifecycle -Force
        Copy-Item -LiteralPath $runAttemptBackup -Destination $runAttempt -Force
        throw
    }
}
