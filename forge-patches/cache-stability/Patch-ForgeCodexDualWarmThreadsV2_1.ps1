param(
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$Lifecycle = Join-Path $Dist "thread-lifecycle-qWE88Dn2.js"
$RunAttempt = Join-Path $Dist "run-attempt-FUyOjGCV.js"

$PatchId = "FORGE_CODEX_DUAL_WARM_THREADS_V2_1"
$V1Marker = "FORGE_CODEX_TRANSIENT_LUNA_V1"
$RequiredBaselineMarker = "FORGE_CODEX_STABLE_TOOL_CATALOG_V2"
$GlobalMapName = "__forgeCodexLunaSidecarsV2"
$ExpectedV1LifecycleSha256 = "d546a85615a77847dbe098c587dec2487d96e5627c4f08cb54d2447f1da8d21d"

$StateDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-dual-warm-threads-v2_1"
$LifecycleBackup = Join-Path $StateDir "thread-lifecycle.v1-original.js"
$RunAttemptBackup = Join-Path $StateDir "run-attempt.original.js"
$Manifest = Join-Path $StateDir "manifest.json"

function Assert-Targets {
    foreach ($Path in @($Lifecycle, $RunAttempt)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Required OpenClaw Codex target not found: $Path"
        }
    }
}

function Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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

function Count-Literal([string]$Text, [string]$Needle) {
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function Replace-ExactlyOnce([string]$Text, [string]$Old, [string]$New, [string]$Name) {
    $Count = Count-Literal $Text $Old
    if ($Count -ne 1) {
        throw "Preflight failed: '$Name' anchor occurred $Count times; expected 1. Nothing was modified."
    }
    return $Text.Replace($Old, $New)
}

function Get-LifecycleBlocks([string]$Text) {
    $NL = Get-Newline $Text

    $BindingRead = "`t`tlet binding = await lifecycleTiming.measure(`"read-binding`", () => params.bindingStore.read(bindingIdentity));"
    $V1Decl = "`t`tlet forgeTransientLunaModelSwitchV1 = false; // $V1Marker"

    $Declarations = Join-Lines @(
        $BindingRead,
        "`t`tconst forgeLunaSidecarsV2 = globalThis.$GlobalMapName ??= new Map(); // $PatchId",
        "`t`tconst forgeLunaSidecarKeyV2 = JSON.stringify(bindingIdentity);",
        "`t`tlet forgeLunaSidecarActiveV2 = false;",
        "`t`tlet forgeTransientLunaModelSwitchV1 = false; // $V1Marker"
    ) $NL

    $ClearOld = Join-Lines @(
        "`t`tconst clearCurrentBinding = async (operation) => {",
        "`t`t`tconst current = binding;",
        "`t`t`tif (!current?.threadId) return;"
    ) $NL

    $ClearNew = Join-Lines @(
        "`t`tconst clearCurrentBinding = async (operation) => {",
        "`t`t`tconst current = binding;",
        "`t`t`tif (!current?.threadId) return;",
        "`t`t`tif (forgeLunaSidecarActiveV2) {",
        "`t`t`t`tforgeLunaSidecarsV2.delete(forgeLunaSidecarKeyV2);",
        "`t`t`t`tbinding = void 0;",
        "`t`t`t`treturn;",
        "`t`t`t}"
    ) $NL

    $V1SwitchOld = Join-Lines @(
        "`t`t`t`tforgeTransientLunaModelSwitchV1 = true;",
        "`t`t`t`tbinding = void 0;"
    ) $NL

    $V2SwitchNew = Join-Lines @(
        "`t`t`t`tforgeTransientLunaModelSwitchV1 = true;",
        "`t`t`t`tforgeLunaSidecarActiveV2 = true;",
        "`t`t`t`tconst forgeLunaSidecarV2 = forgeLunaSidecarsV2.get(forgeLunaSidecarKeyV2);",
        "`t`t`t`tif (forgeLunaSidecarV2?.threadId) {",
        "`t`t`t`t`tembeddedAgentLog.debug(`"codex app-server GPT-5.6 Sol/Terra -> Luna switch; resuming parked Luna sidecar and preserving durable Sol/Terra binding`", {",
        "`t`t`t`t`t`tthreadId: forgeLunaSidecarV2.threadId,",
        "`t`t`t`t`t`tparkedDurableThreadId: binding.threadId",
        "`t`t`t`t`t});",
        "`t`t`t`t`tbinding = forgeLunaSidecarV2;",
        "`t`t`t`t} else {",
        "`t`t`t`t`tembeddedAgentLog.debug(`"codex app-server GPT-5.6 Sol/Terra -> Luna switch; starting first Luna sidecar and preserving durable Sol/Terra binding`", { threadId: binding.threadId });",
        "`t`t`t`t`tbinding = void 0;",
        "`t`t`t`t}"
    ) $NL

    $ResumeWriteOldExact = Join-Lines @(
        "`t`t`t`tif (!await lifecycleTiming.measure(`"thread-resume-write-binding`", () => params.bindingStore.mutate(bindingIdentity, {",
        "`t`t`t`t`tkind: `"patch`",",
        "`t`t`t`t`tthreadId: resumeBinding.threadId,",
        "`t`t`t`t`tpatch: resumePatch",
        "`t`t`t`t}))) throw new CodexThreadBindingConflictError(resumeBinding.threadId, `"committing a resumed thread`");"
    ) $NL

    $ResumeWriteNew = Join-Lines @(
        "`t`t`t`tif (forgeLunaSidecarActiveV2) {",
        "`t`t`t`t`tforgeLunaSidecarsV2.set(forgeLunaSidecarKeyV2, {",
        "`t`t`t`t`t`t...resumeBinding,",
        "`t`t`t`t`t`t...resumePatch,",
        "`t`t`t`t`t`tthreadId: response.thread.id",
        "`t`t`t`t`t});",
        "`t`t`t`t} else if (!await lifecycleTiming.measure(`"thread-resume-write-binding`", () => params.bindingStore.mutate(bindingIdentity, {",
        "`t`t`t`t`tkind: `"patch`",",
        "`t`t`t`t`tthreadId: resumeBinding.threadId,",
        "`t`t`t`t`tpatch: resumePatch",
        "`t`t`t`t}))) throw new CodexThreadBindingConflictError(resumeBinding.threadId, `"committing a resumed thread`");"
    ) $NL

    # Anchor the fresh-thread path with its unique summary block.  The bare
    # thread-ready marker also appears on the resume path in this build.
    $FreshThreadReady = Join-Lines @(
        "`t`tlifecycleTiming.mark(`"thread-ready`");",
        "`t`tlifecycleTiming.logSummary({",
        "`t`t`trunId: params.params.runId,",
        "`t`t`tsessionId: params.params.sessionId,",
        "`t`t`tsessionKey: params.params.sessionKey,",
        "`t`t`tthreadId: response.thread.id,",
        "`t`t`taction: rotatedContextEngineBinding ? `"rotated`" : `"started`"",
        "`t`t});"
    ) $NL
    $SidecarCapture = Join-Lines @(
        "`t`tif (forgeLunaSidecarActiveV2) {",
        "`t`t`tforgeLunaSidecarsV2.set(forgeLunaSidecarKeyV2, {",
        "`t`t`t`tthreadId: response.thread.id,",
        "`t`t`t`tcwd: params.cwd,",
        "`t`t`t`tauthProfileId: params.params.authProfileId,",
        "`t`t`t`tmodel: response.model ?? startParams.model ?? params.params.modelId,",
        "`t`t`t`tmodelProvider: normalizeBindingModelProvider(params.params.authProfileId, response.modelProvider ?? requestModelProvider ?? startModelProvider ?? modelProvider),",
        "`t`t`t`tdynamicToolsFingerprint,",
        "`t`t`t`tdynamicToolsContainDeferred,",
        "`t`t`t`twebSearchThreadConfigFingerprint,",
        "`t`t`t`tuserMcpServersFingerprint,",
        "`t`t`t`tmcpServersFingerprint: nextMcpServersFingerprint,",
        "`t`t`t`tnetworkProxyProfileName: params.appServer.networkProxy?.profileName,",
        "`t`t`t`tnetworkProxyConfigFingerprint,",
        "`t`t`t`tnativeHookRelayGeneration: finalConfigPatch.nativeHookRelayGeneration,",
        "`t`t`t`tappServerRuntimeFingerprint: params.appServerRuntimeFingerprint,",
        "`t`t`t`tpluginAppsFingerprint: pluginThreadConfig?.fingerprint,",
        "`t`t`t`tpluginAppsInputFingerprint: pluginThreadConfig?.inputFingerprint,",
        "`t`t`t`tpluginAppPolicyContext: pluginThreadConfig?.policyContext,",
        "`t`t`t`tcontextEngine: contextEngineBinding,",
        "`t`t`t`tenvironmentSelectionFingerprint",
        "`t`t`t});",
        "`t`t}",
        $FreshThreadReady
    ) $NL

    return [pscustomobject]@{
        NL = $NL
        BindingRead = $BindingRead
        Declarations = $Declarations
        V1Decl = $V1Decl
        ClearOld = $ClearOld
        ClearNew = $ClearNew
        V1SwitchOld = $V1SwitchOld
        V2SwitchNew = $V2SwitchNew
        ResumeWriteOld = $ResumeWriteOldExact
        ResumeWriteNew = $ResumeWriteNew
        ThreadReady = $FreshThreadReady
        SidecarCapture = $SidecarCapture
    }
}

function Get-RunAttemptBlocks([string]$Text) {
    $NL = Get-Newline $Text

    $PrecomputeOld = "`tif (precomputeNoContextEngineStaleBindingProjection(startupBinding)) await rebuildCodexPromptBuildFromCurrentProjection();"
    $PrecomputeNew = Join-Lines @(
        "`tconst forgeLunaSidecarsForContinuityV2 = globalThis.$GlobalMapName; // $PatchId",
        "`tconst forgeRequestedModelForContinuityV2 = (params.modelId ?? `"`").trim().toLowerCase().split(`"/`").at(-1);",
        "`tconst forgeLunaContinuitySidecarV2 = forgeLunaSidecarsForContinuityV2?.get(JSON.stringify(bindingIdentity));",
        "`tconst forgeContinuityBindingV2 = forgeRequestedModelForContinuityV2 === `"gpt-5.6-luna`" && forgeLunaContinuitySidecarV2?.threadId ? forgeLunaContinuitySidecarV2 : startupBinding;",
        "`tif (precomputeNoContextEngineStaleBindingProjection(forgeContinuityBindingV2)) await rebuildCodexPromptBuildFromCurrentProjection();"
    ) $NL
    $CoverageOld = Join-Lines @(
        "async function markCodexAppServerBindingCoveredThroughTurn(params) {",
        "`tawait params.bindingStore.mutate(params.identity, {",
        "`t`tkind: `"patch`",",
        "`t`tthreadId: params.threadId,",
        "`t`tpatch: { historyCoveredThrough: (/* @__PURE__ */ new Date()).toISOString() }",
        "`t});",
        "}"
    ) $NL

    $CoverageNew = Join-Lines @(
        "async function markCodexAppServerBindingCoveredThroughTurn(params) {",
        "`tconst historyCoveredThrough = (/* @__PURE__ */ new Date()).toISOString();",
        "`tconst forgeLunaSidecarsV2 = globalThis.$GlobalMapName; // $PatchId",
        "`tconst forgeLunaSidecarKeyV2 = JSON.stringify(params.identity);",
        "`tconst forgeLunaSidecarV2 = forgeLunaSidecarsV2?.get(forgeLunaSidecarKeyV2);",
        "`tif (forgeLunaSidecarV2?.threadId === params.threadId) {",
        "`t`tforgeLunaSidecarsV2.set(forgeLunaSidecarKeyV2, { ...forgeLunaSidecarV2, historyCoveredThrough });",
        "`t`treturn;",
        "`t}",
        "`tawait params.bindingStore.mutate(params.identity, {",
        "`t`tkind: `"patch`",",
        "`t`tthreadId: params.threadId,",
        "`t`tpatch: { historyCoveredThrough }",
        "`t});",
        "}"
    ) $NL

    return [pscustomobject]@{
        NL = $NL
        PrecomputeOld = $PrecomputeOld
        PrecomputeNew = $PrecomputeNew
        CoverageOld = $CoverageOld
        CoverageNew = $CoverageNew
    }
}

function Show-Status {
    Assert-Targets
    $L = [System.IO.File]::ReadAllText($Lifecycle)
    $R = [System.IO.File]::ReadAllText($RunAttempt)
    $LB = Get-LifecycleBlocks $L
    $RB = Get-RunAttemptBlocks $R

    $Baseline = $L.Contains($RequiredBaselineMarker)
    $LifecycleSha = Sha $Lifecycle
    $V1HashMatch = $LifecycleSha -eq $ExpectedV1LifecycleSha256
    $V1 = $L.Contains($V1Marker)
    $V2Lifecycle = $L.Contains($PatchId)
    $V2RunAttempt = $R.Contains($PatchId)
    $SidecarMap = $L.Contains($GlobalMapName)
    $ContinuityHook = $R.Contains("forgeContinuityBindingV2")
    $CoverageHook = $R.Contains("forgeLunaSidecarKeyV2")
    $V1SwitchAnchor = $L.Contains($LB.V1SwitchOld)
    $ResumeNativeAnchor = $L.Contains($LB.ResumeWriteOld)
    $PrecomputeNativeAnchor = $R.Contains($RB.PrecomputeOld)
    $CoverageNativeAnchor = $R.Contains($RB.CoverageOld)

    Write-Host ""
    Write-Host "Forge Codex Dual Warm Threads V2.1"
    Write-Host ""
    Write-Host "Targets:"
    Write-Host "  $Lifecycle"
    Write-Host "  $RunAttempt"
    Write-Host ""
    Write-Host "State:"
    Write-Host "  Stable Tool Catalogue V2 present: $Baseline"
    Write-Host "  Transient Luna V1 lineage present: $V1"
    Write-Host "  Verified V1 lifecycle hash match:   $V1HashMatch"
    Write-Host "  V2 lifecycle marker present:       $V2Lifecycle"
    Write-Host "  V2 run-attempt marker present:     $V2RunAttempt"
    Write-Host "  Luna sidecar map hook present:     $SidecarMap"
    Write-Host "  Luna continuity hook present:      $ContinuityHook"
    Write-Host "  Luna coverage hook present:        $CoverageHook"
    Write-Host "  V1 switch anchor still present:    $V1SwitchAnchor"
    Write-Host "  Native resume-write anchor:        $ResumeNativeAnchor"
    Write-Host "  Native continuity anchor:          $PrecomputeNativeAnchor"
    Write-Host "  Native coverage anchor:            $CoverageNativeAnchor"
    Write-Host "  Backup manifest exists:            $(Test-Path -LiteralPath $Manifest)"
    Write-Host "  Lifecycle SHA256:                  $LifecycleSha"
    Write-Host "  Run-attempt SHA256:                $(Sha $RunAttempt)"
    Write-Host ""

    if ($V2Lifecycle -and $V2RunAttempt -and $SidecarMap -and $ContinuityHook -and $CoverageHook) {
        Write-Host "STATUS: INSTALLED"
    }
    elseif ($Baseline -and $V1 -and $V1HashMatch -and -not $V2Lifecycle -and -not $V2RunAttempt -and $V1SwitchAnchor -and $ResumeNativeAnchor -and $PrecomputeNativeAnchor -and $CoverageNativeAnchor) {
        Write-Host "STATUS: READY TO APPLY"
    }
    else {
        Write-Host "STATUS: PARTIAL / UNEXPECTED - do not apply or restart until inspected"
    }
}

function Apply-Patch {
    Assert-Targets

    $L = [System.IO.File]::ReadAllText($Lifecycle)
    $R = [System.IO.File]::ReadAllText($RunAttempt)

    if ($L.Contains($PatchId) -or $R.Contains($PatchId)) {
        Write-Host "Dual Warm Threads V2.1 already appears at least partially installed; no changes made."
        Show-Status
        return
    }
    if (-not $L.Contains($RequiredBaselineMarker)) {
        throw "Required known-good baseline '$RequiredBaselineMarker' is not present. Refusing to patch."
    }
    if (-not $L.Contains($V1Marker)) {
        throw "Transient Luna V1 is not present. V2 upgrades the verified V1 state; refusing to patch a different baseline."
    }
    $CurrentV1Sha = Sha $Lifecycle
    if ($CurrentV1Sha -ne $ExpectedV1LifecycleSha256) {
        throw "Lifecycle hash does not match the verified Transient Luna V1 build. Expected $ExpectedV1LifecycleSha256, got $CurrentV1Sha. Refusing to patch."
    }

    $LB = Get-LifecycleBlocks $L
    $RB = Get-RunAttemptBlocks $R

    # Full preflight before writing either target.
    $Checks = @(
        @($L, $LB.BindingRead, "lifecycle binding-read"),
        @($L, $LB.V1Decl, "V1 declaration"),
        @($L, $LB.ClearOld, "clearCurrentBinding"),
        @($L, $LB.V1SwitchOld, "V1 Sol-to-Luna switch"),
        @($L, $LB.ResumeWriteOld, "resume binding write"),
        @($L, $LB.ThreadReady, "unique fresh-thread ready block"),
        @($R, $RB.PrecomputeOld, "continuity precompute"),
        @($R, $RB.CoverageOld, "binding coverage helper")
    )
    foreach ($Check in $Checks) {
        $Count = Count-Literal ([string]$Check[0]) ([string]$Check[1])
        if ($Count -ne 1) {
            throw "Preflight failed: '$($Check[2])' occurred $Count times; expected 1. Nothing was modified."
        }
    }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    $LifecycleOriginalSha = Sha $Lifecycle
    $RunAttemptOriginalSha = Sha $RunAttempt

    if ((Test-Path -LiteralPath $Manifest) -or (Test-Path -LiteralPath $LifecycleBackup) -or (Test-Path -LiteralPath $RunAttemptBackup)) {
        throw "V2.1 backup/state files already exist. Refusing to overwrite prior rollback state: $StateDir"
    }

    Copy-Item -LiteralPath $Lifecycle -Destination $LifecycleBackup
    Copy-Item -LiteralPath $RunAttempt -Destination $RunAttemptBackup

    try {
        $LP = $L
        $LP = Replace-ExactlyOnce $LP $LB.V1Decl "" "move V1 transient flag declaration"
        $LP = Replace-ExactlyOnce $LP $LB.BindingRead $LB.Declarations "insert sidecar state"
        $LP = Replace-ExactlyOnce $LP $LB.ClearOld $LB.ClearNew "sidecar-aware clearCurrentBinding"
        $LP = Replace-ExactlyOnce $LP $LB.V1SwitchOld $LB.V2SwitchNew "reuse parked Luna sidecar"
        $LP = Replace-ExactlyOnce $LP $LB.ResumeWriteOld $LB.ResumeWriteNew "sidecar resume commit"
        $LP = Replace-ExactlyOnce $LP $LB.ThreadReady $LB.SidecarCapture "fresh Luna sidecar capture at unique start block"

        $RP = $R
        $RP = Replace-ExactlyOnce $RP $RB.PrecomputeOld $RB.PrecomputeNew "Luna continuity precompute"
        $RP = Replace-ExactlyOnce $RP $RB.CoverageOld $RB.CoverageNew "Luna history coverage"

        Write-NoBom $Lifecycle $LP
        Write-NoBom $RunAttempt $RP

        Node-Check $Lifecycle
        Node-Check $RunAttempt

        $LV = [System.IO.File]::ReadAllText($Lifecycle)
        $RV = [System.IO.File]::ReadAllText($RunAttempt)
        if (-not $LV.Contains($PatchId) -or -not $RV.Contains($PatchId)) {
            throw "Verification failed: V2.1 markers are not present in both targets."
        }
        if (-not $LV.Contains($V1Marker)) {
            throw "Verification failed: V1 lineage marker disappeared."
        }
        if (-not $LV.Contains("forgeLunaSidecarsV2.set") -or -not $RV.Contains("forgeContinuityBindingV2")) {
            throw "Verification failed: expected sidecar/continuity hooks are missing."
        }

        $LifecyclePatchedSha = Sha $Lifecycle
        $RunAttemptPatchedSha = Sha $RunAttempt

        $ManifestData = [ordered]@{
            patchId = $PatchId
            baselinePatchId = $V1Marker
            appliedAt = (Get-Date).ToString("o")
            files = @(
                [ordered]@{
                    target = $Lifecycle
                    backup = $LifecycleBackup
                    originalSha256 = $LifecycleOriginalSha
                    patchedSha256 = $LifecyclePatchedSha
                },
                [ordered]@{
                    target = $RunAttempt
                    backup = $RunAttemptBackup
                    originalSha256 = $RunAttemptOriginalSha
                    patchedSha256 = $RunAttemptPatchedSha
                }
            )
        }
        $ManifestData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Manifest -Encoding UTF8

        Write-Host ""
        Write-Host "DUAL WARM THREADS V2.1 APPLY PASS"
        Write-Host ""
        Write-Host "Behavior:"
        Write-Host "  Sol/Terra remains the durable OpenClaw binding"
        Write-Host "  Luna gets one parked in-memory sidecar thread per binding identity"
        Write-Host "  Repeated Luna turns resume the same Luna thread"
        Write-Host "  Returning to Sol/Terra resumes the original durable thread"
        Write-Host "  Luna continuity uses its own historyCoveredThrough marker"
        Write-Host "  Gateway restart intentionally forgets Luna sidecars (one cold Luna turn after restart)"
        Write-Host ""
        Write-Host "Lifecycle SHA256:"
        Write-Host "  before: $LifecycleOriginalSha"
        Write-Host "  after:  $LifecyclePatchedSha"
        Write-Host "Run-attempt SHA256:"
        Write-Host "  before: $RunAttemptOriginalSha"
        Write-Host "  after:  $RunAttemptPatchedSha"
        Write-Host ""
        Write-Host "Restart once:"
        Write-Host "  openclaw gateway restart"
        Write-Host ""
    }
    catch {
        Copy-Item -LiteralPath $LifecycleBackup -Destination $Lifecycle -Force
        Copy-Item -LiteralPath $RunAttemptBackup -Destination $RunAttempt -Force
        throw
    }
}

function Rollback-Patch {
    Assert-Targets

    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        throw "Rollback manifest not found: $Manifest"
    }
    if (-not (Test-Path -LiteralPath $LifecycleBackup -PathType Leaf) -or -not (Test-Path -LiteralPath $RunAttemptBackup -PathType Leaf)) {
        throw "One or more V2 rollback backups are missing from: $StateDir"
    }

    $M = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ([string]$M.patchId -ne $PatchId) {
        throw "Rollback manifest patch id mismatch."
    }

    $LifecycleEntry = $M.files | Where-Object { [string]$_.target -eq $Lifecycle } | Select-Object -First 1
    $RunAttemptEntry = $M.files | Where-Object { [string]$_.target -eq $RunAttempt } | Select-Object -First 1
    if (-not $LifecycleEntry -or -not $RunAttemptEntry) {
        throw "Rollback manifest does not contain both target files."
    }

    if ((Sha $Lifecycle) -ne [string]$LifecycleEntry.patchedSha256) {
        throw "Lifecycle target changed after V2 was applied. Refusing to overwrite newer edits."
    }
    if ((Sha $RunAttempt) -ne [string]$RunAttemptEntry.patchedSha256) {
        throw "Run-attempt target changed after V2 was applied. Refusing to overwrite newer edits."
    }

    Copy-Item -LiteralPath $LifecycleBackup -Destination $Lifecycle -Force
    Copy-Item -LiteralPath $RunAttemptBackup -Destination $RunAttempt -Force

    Node-Check $Lifecycle
    Node-Check $RunAttempt

    if ((Sha $Lifecycle) -ne [string]$LifecycleEntry.originalSha256) {
        throw "Lifecycle rollback SHA256 verification failed."
    }
    if ((Sha $RunAttempt) -ne [string]$RunAttemptEntry.originalSha256) {
        throw "Run-attempt rollback SHA256 verification failed."
    }

    $L = [System.IO.File]::ReadAllText($Lifecycle)
    $R = [System.IO.File]::ReadAllText($RunAttempt)
    if ($L.Contains($PatchId) -or $R.Contains($PatchId)) {
        throw "Rollback verification failed: V2 marker still present."
    }
    if (-not $L.Contains($V1Marker)) {
        throw "Rollback verification failed: expected V1 baseline was not restored."
    }

    Write-Host ""
    Write-Host "DUAL WARM THREADS V2.1 ROLLBACK PASS"
    Write-Host ""
    Write-Host "Restored the verified Transient Luna V1 baseline."
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
}

switch ($Action) {
    "status"   { Show-Status }
    "apply"    { Apply-Patch }
    "rollback" { Rollback-Patch }
}
