# Forge 1.2.1 - Sol 80k Rolling Native Sessions
#
# Starting point:
#   Forge 1.2.0 live-proven Luna native canonical bootstrap.
#
# Changes:
#   1. Sol completed-turn rollover threshold becomes config-driven.
#   2. continuity.solRolloverTokens changes 200000 -> 80000.
#   3. The proven ~30k native canonical bootstrap runs on genuinely fresh
#      Sol threads as well as fresh Luna threads.
#   4. Canon/native-delta exact-pair dedupe applies to either model side
#      when a fresh canonical bootstrap has just occurred.
#
# Luna rollover behaviour is NOT changed:
# the existing post-turn hardcap path returns before the hardcap block when
# the current thread is the Luna sidecar.
#
# Safety:
# - exact live SHA gates
# - exact current config gate
# - structural anchor checks
# - staged candidate + node --check
# - timestamped byte-for-byte run/config backups
# - immediate recheck before mutation
# - 120 second RPC health window
# - automatic rollback on any post-mutation failure
# - one-command rollback script

param(
    [switch]$PreflightOnly
)

& {
    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version Latest

    $Dist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
    $RunAttempt = Join-Path $Dist "run-attempt-FUyOjGCV.js"
    $Provider = Join-Path $Dist "provider-capabilities-CDnHbmUZ.js"
    $Config = "$env:USERPROFILE\.openclaw\openclaw.json"

    $ExpectedRunHash = "e406db4b0c052b784d7a363ab048380ed9136ecb429fa46d195f01de40f4eb1c"
    $ExpectedProviderHash = "9f7eb3c6bdbdaba427858b94f7c4e7e57308a1bbf1ad92451aea83f70855467c"
    $ExpectedOldSolRollover = 200000
    $NewSolRollover = 80000

    $LunaBootstrapMarker = "FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_30K_V5"
    $PostTurnMarker = "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3"
    $RolloverMarker = "FORGE_SOL_ROLLOVER_CONFIG_V121"
    $SolBootstrapMarker = "FORGE_SOL_NATIVE_CANON_BOOTSTRAP_V121"
    $BothDedupeMarker = "FORGE_NATIVE_CANON_DELTA_DEDUPE_BOTH_V121"

    function Sha256([string]$Path) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function Count-Literal([string]$Text, [string]$Needle) {
        if ([string]::IsNullOrEmpty($Needle)) { return 0 }
        $Count = 0
        $Offset = 0
        while ($true) {
            $Index = $Text.IndexOf($Needle, $Offset, [System.StringComparison]::Ordinal)
            if ($Index -lt 0) { break }
            $Count++
            $Offset = $Index + $Needle.Length
        }
        return $Count
    }

    function Read-ConfigObject {
        return ([IO.File]::ReadAllText($Config) | ConvertFrom-Json)
    }

    function Read-SolRollover {
        $Obj = Read-ConfigObject
        $Monitor = $Obj.plugins.entries.'forge-discord-monitor'.config
        if ($null -eq $Monitor) {
            throw "forge-discord-monitor config missing from openclaw.json."
        }
        if ($null -eq $Monitor.continuity) {
            throw "forge-discord-monitor continuity config missing from openclaw.json."
        }
        return [int64]$Monitor.continuity.solRolloverTokens
    }

    function Wait-GatewayHealthy([int]$TimeoutSeconds = 120, [int]$DelaySeconds = 5) {
        $Watch = [Diagnostics.Stopwatch]::StartNew()
        $Attempt = 0
        while ($Watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $Attempt++
            $Elapsed = [Math]::Floor($Watch.Elapsed.TotalSeconds)
            Write-Host "Gateway health probe $Attempt - elapsed ${Elapsed}s / ${TimeoutSeconds}s..."
            & openclaw gateway status --deep --require-rpc
            if ($LASTEXITCODE -eq 0) {
                $Watch.Stop()
                return $true
            }
            if ($Watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
        $Watch.Stop()
        return $false
    }

    foreach ($Path in @($RunAttempt, $Provider, $Config)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Required live file missing: $Path"
        }
    }

    $RunHash = Sha256 $RunAttempt
    $ProviderHash = Sha256 $Provider
    $ConfigHash = Sha256 $Config
    $CurrentSolRollover = Read-SolRollover

    if ($RunHash -ne $ExpectedRunHash) {
        throw @"
run-attempt is not the exact banked Forge 1.2.0 live state.
Expected: $ExpectedRunHash
Actual:   $RunHash

Nothing changed.
"@
    }

    if ($ProviderHash -ne $ExpectedProviderHash) {
        throw @"
provider-capabilities is not the exact banked Forge 1.2.0 live state.
Expected: $ExpectedProviderHash
Actual:   $ProviderHash

Nothing changed.
"@
    }

    if ($CurrentSolRollover -ne $ExpectedOldSolRollover) {
        throw @"
Unexpected current continuity.solRolloverTokens.
Expected: $ExpectedOldSolRollover
Actual:   $CurrentSolRollover

Nothing changed.
"@
    }

    $Original = [IO.File]::ReadAllText($RunAttempt)

    foreach ($Required in @(
        $LunaBootstrapMarker,
        $PostTurnMarker,
        "FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4",
        "FORGE_CODEX_BIDIRECTIONAL_NATIVE_DELTA_V2",
        "FORGE_CODEX_DUAL_WARM_THREADS_V2_1"
    )) {
        if ((Count-Literal $Original $Required) -lt 1) {
            throw "Required 1.2.0 marker missing: $Required"
        }
    }

    foreach ($NewMarker in @($RolloverMarker, $SolBootstrapMarker, $BothDedupeMarker)) {
        if ($Original.Contains($NewMarker)) {
            throw "1.2.1 marker already present: $NewMarker"
        }
    }

    # Prove the principal hardcap remains after Luna's early-return sidecar path.
    $LunaReturnAnchor = 'if (forgeLunaSidecarV2?.threadId === params.threadId) {'
    $HardcapIndex = $Original.IndexOf($PostTurnMarker, [System.StringComparison]::Ordinal)
    $LunaReturnIndex = $Original.IndexOf($LunaReturnAnchor, [System.StringComparison]::Ordinal)

    if ($LunaReturnIndex -lt 0 -or $HardcapIndex -lt 0 -or $LunaReturnIndex -ge $HardcapIndex) {
        throw "Could not prove Luna sidecar early-return path precedes the principal hardcap."
    }

    $CandidateText = $Original

    # ------------------------------------------------------------------
    # 1. Pass the resolved OpenClaw config into the existing post-turn
    #    native-coverage helper, so the hardcap has one policy authority.
    # ------------------------------------------------------------------
    $CoverageCallAnchor = @'
                                codexHome: appServer.start.env?.CODEX_HOME
                        });
'@

    if ((Count-Literal $CandidateText $CoverageCallAnchor) -ne 1) {
        throw "Post-turn coverage-call anchor is not exactly one."
    }

    $CoverageCallReplacement = @'
                                codexHome: appServer.start.env?.CODEX_HOME,
                                config: params.config // FORGE_SOL_ROLLOVER_CONFIG_V121
                        });
'@

    $CandidateText = $CandidateText.Replace($CoverageCallAnchor, $CoverageCallReplacement)

    # ------------------------------------------------------------------
    # 2. Replace the emergency hardcoded 200k Sol threshold with the
    #    configured continuity.solRolloverTokens value.
    # ------------------------------------------------------------------
    $Threshold200 = @'
        if (
                forgePostTurnNativeTokensV3 !== void 0 &&
                forgePostTurnNativeTokensV3 >= 200_000
        ) {
'@

    if ((Count-Literal $CandidateText $Threshold200) -ne 1) {
        throw "Current 200k Sol hardcap block is not exactly one."
    }

    $ThresholdConfigured = @'
        const forgePostTurnHardcapRawV121 =
                params.config?.plugins?.entries?.["forge-discord-monitor"]?.config?.continuity?.solRolloverTokens;
        const forgePostTurnHardcapTokensV121 =
                typeof forgePostTurnHardcapRawV121 === "number" &&
                Number.isFinite(forgePostTurnHardcapRawV121) &&
                forgePostTurnHardcapRawV121 > 0
                        ? Math.floor(forgePostTurnHardcapRawV121)
                        : 80_000;

        if (
                forgePostTurnNativeTokensV3 !== void 0 &&
                forgePostTurnNativeTokensV3 >= forgePostTurnHardcapTokensV121
        ) {
'@

    $CandidateText = $CandidateText.Replace($Threshold200, $ThresholdConfigured)

    # Make the diagnostic text truthful without depending on the old literal.
    $CandidateText = [regex]::Replace(
        $CandidateText,
        '"forge native thread reached completed-turn (?:60k|120k|200k) hardcap; fresh rollover armed"',
        '"forge native Sol thread reached completed-turn configured hardcap; fresh rollover armed"',
        1
    )
    $CandidateText = [regex]::Replace(
        $CandidateText,
        'hardcap: (?:60_000|120_000|200_000)',
        'hardcap: forgePostTurnHardcapTokensV121',
        1
    )

    # ------------------------------------------------------------------
    # 3. Reuse the live-proven 1.2.0 native canon bootstrap on fresh Sol.
    #    Warm/resumed Sol is unaffected by the lifecycle === "started" gate.
    # ------------------------------------------------------------------
    $LunaOnlyGuard =
        '(params.modelId ?? "").trim().toLowerCase().split("/").at(-1) === "gpt-5.6-luna"'

    if ((Count-Literal $CandidateText $LunaOnlyGuard) -ne 1) {
        throw "Fresh-Luna native bootstrap model gate is not exactly one."
    }

    $BothModelGuard =
        '["gpt-5.6-luna", "gpt-5.6-sol"].includes((params.modelId ?? "").trim().toLowerCase().split("/").at(-1)) /* FORGE_SOL_NATIVE_CANON_BOOTSTRAP_V121 */'

    $CandidateText = $CandidateText.Replace($LunaOnlyGuard, $BothModelGuard)

    # The bootstrap tail already contains many recent cross-model exchanges.
    # When a fresh bootstrap ran, allow exact-pair dedupe on either target side.
    $LunaOnlyDedupe = 'forgeNativeDeltaTargetSideV2 === "luna" &&'
    if ((Count-Literal $CandidateText $LunaOnlyDedupe) -ne 1) {
        throw "Fresh-canon native-delta dedupe model gate is not exactly one."
    }

    $CandidateText = $CandidateText.Replace(
        $LunaOnlyDedupe,
        'forgeNativeDeltaTargetSideV2 !== void 0 && /* FORGE_NATIVE_CANON_DELTA_DEDUPE_BOTH_V121 */'
    )

    # Make fresh-bootstrap logging model-neutral.
    $CandidateText = $CandidateText.Replace(
        '"forge fresh Luna canonical native bootstrap injected"',
        '"forge fresh canonical native bootstrap injected"'
    )
    $CandidateText = $CandidateText.Replace(
        '"forge fresh Luna canonical native bootstrap had no messages"',
        '"forge fresh canonical native bootstrap had no messages"'
    )

    # ------------------------------------------------------------------
    # Candidate invariants.
    # ------------------------------------------------------------------
    foreach ($Required in @(
        $LunaBootstrapMarker,
        $RolloverMarker,
        $SolBootstrapMarker,
        $BothDedupeMarker,
        "forgePostTurnHardcapTokensV121",
        '["gpt-5.6-luna", "gpt-5.6-sol"].includes'
    )) {
        if ((Count-Literal $CandidateText $Required) -lt 1) {
            throw "Required 1.2.1 candidate marker/code missing: $Required"
        }
    }

    if ((Count-Literal $CandidateText 'forgePostTurnNativeTokensV3 >= 200_000') -ne 0) {
        throw "Hardcoded 200k Sol threshold survived candidate build."
    }

    if ((Count-Literal $CandidateText 'forgePostTurnNativeTokensV3 >= forgePostTurnHardcapTokensV121') -ne 1) {
        throw "Configured Sol hardcap comparison is not exactly one."
    }

    if ((Count-Literal $CandidateText 'thread.lifecycle.action === "started"') -lt 1) {
        throw "Fresh-thread lifecycle gate disappeared."
    }

    if ((Count-Literal $CandidateText 'forgeCanonicalSessionFile: true') -ne 1) {
        throw "Canonical-file bypass is no longer scoped to exactly one bootstrap read."
    }

    # Existing three native injection sites remain:
    # fresh canon, native delta, transient cleanup.
    if ((Count-Literal $CandidateText 'thread/inject_items') -ne 3) {
        throw "Expected exactly three thread/inject_items sites after 1.2.1 candidate build."
    }

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $StageDir = "$env:USERPROFILE\Desktop\forge-v121-sol-rolling-$Stamp"
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

    $RunBackup = Join-Path $StageDir "run-attempt.pre-v121-backup.js"
    $ConfigBackup = Join-Path $StageDir "openclaw.pre-v121-backup.json"
    $ProviderReference = Join-Path $StageDir "provider-capabilities.v120-reference.js"
    $RunCandidate = Join-Path $StageDir "run-attempt.v121-sol-rolling-candidate.js"
    $RollbackPath = Join-Path $StageDir "ROLLBACK-FORGE-1.2.1.ps1"

    [IO.File]::Copy($RunAttempt, $RunBackup, $true)
    [IO.File]::Copy($Config, $ConfigBackup, $true)
    [IO.File]::Copy($Provider, $ProviderReference, $true)

    if ((Sha256 $RunBackup) -ne $ExpectedRunHash) {
        throw "Run backup SHA mismatch."
    }
    if ((Sha256 $ConfigBackup) -ne $ConfigHash) {
        throw "Config backup SHA mismatch."
    }
    if ((Sha256 $ProviderReference) -ne $ExpectedProviderHash) {
        throw "Provider reference SHA mismatch."
    }

    [IO.File]::WriteAllText(
        $RunCandidate,
        $CandidateText,
        [Text.UTF8Encoding]::new($false)
    )

    & node --check $RunCandidate
    if ($LASTEXITCODE -ne 0) {
        throw "1.2.1 run-attempt candidate failed node --check."
    }

    $CandidateHash = Sha256 $RunCandidate

    $RollbackText = @"
`$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

`$RunAttempt = "$RunAttempt"
`$Config = "$Config"
`$Provider = "$Provider"
`$RunBackup = "$RunBackup"
`$ConfigBackup = "$ConfigBackup"
`$ExpectedRunHash = "$ExpectedRunHash"
`$ExpectedConfigHash = "$ConfigHash"
`$ExpectedProviderHash = "$ExpectedProviderHash"

function Sha256([string]`$Path) {
    return (Get-FileHash -LiteralPath `$Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ((Sha256 `$RunBackup) -ne `$ExpectedRunHash) {
    throw "Rollback run backup SHA mismatch."
}
if ((Sha256 `$ConfigBackup) -ne `$ExpectedConfigHash) {
    throw "Rollback config backup SHA mismatch."
}
if ((Sha256 `$Provider) -ne `$ExpectedProviderHash) {
    throw "Provider changed since 1.2.1 apply; refusing partial rollback."
}

[IO.File]::Copy(`$RunBackup, `$RunAttempt, `$true)
[IO.File]::Copy(`$ConfigBackup, `$Config, `$true)

& node --check `$RunAttempt
if (`$LASTEXITCODE -ne 0) {
    throw "Restored 1.2.0 run-attempt failed node --check."
}
if ((Sha256 `$RunAttempt) -ne `$ExpectedRunHash) {
    throw "Restored 1.2.0 run-attempt SHA mismatch."
}
if ((Sha256 `$Config) -ne `$ExpectedConfigHash) {
    throw "Restored pre-1.2.1 config SHA mismatch."
}

openclaw gateway restart
if (`$LASTEXITCODE -ne 0) {
    throw "Gateway restart failed during rollback."
}

`$Healthy = `$false
`$Watch = [Diagnostics.Stopwatch]::StartNew()
while (`$Watch.Elapsed.TotalSeconds -lt 120) {
    openclaw gateway status --deep --require-rpc
    if (`$LASTEXITCODE -eq 0) {
        `$Healthy = `$true
        break
    }
    Start-Sleep -Seconds 5
}
`$Watch.Stop()

if (-not `$Healthy) {
    throw "1.2.0 bytes/config restored, but gateway RPC did not become healthy within 120 seconds."
}

Write-Host ""
Write-Host "PASS - rolled Forge 1.2.1 back to exact banked 1.2.0 run + pre-1.2.1 config." -ForegroundColor Green
Write-Host "Run SHA:    `$(Sha256 `$RunAttempt)"
Write-Host "Config SHA: `$(Sha256 `$Config)"
"@

    [IO.File]::WriteAllText(
        $RollbackPath,
        $RollbackText,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host ""
    Write-Host "=== FORGE 1.2.1 SOL ROLLING PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host "Run live SHA:        $RunHash"
    Write-Host "Provider live SHA:   $ProviderHash"
    Write-Host "Config live SHA:     $ConfigHash"
    Write-Host "Current Sol rollover:$CurrentSolRollover"
    Write-Host "Target Sol rollover: $NewSolRollover"
    Write-Host "Candidate SHA:       $CandidateHash"
    Write-Host "Stage:               $StageDir"
    Write-Host "Rollback:            powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
    Write-Host "Syntax:              PASS"
    Write-Host ""
    Write-Host "1.2.1 behaviour:"
    Write-Host "  - Sol hardcap reads continuity.solRolloverTokens"
    Write-Host "  - config moves Sol 200k -> 80k"
    Write-Host "  - Luna sidecar still bypasses the principal hardcap"
    Write-Host "  - fresh Sol gets the proven ~30k native canon bootstrap"
    Write-Host "  - warm Sol is unchanged until its completed-turn hardcap is crossed"
    Write-Host "  - fresh Luna bootstrap remains enabled"
    Write-Host ""

    if ($PreflightOnly) {
        Write-Host "PASS - PREFLIGHT ONLY. Live files, config and gateway unchanged." -ForegroundColor Green
        return
    }

    $MutationStarted = $false
    try {
        # Recheck immediately before touching anything.
        if ((Sha256 $RunAttempt) -ne $ExpectedRunHash) {
            throw "run-attempt changed after preflight. Nothing modified."
        }
        if ((Sha256 $Provider) -ne $ExpectedProviderHash) {
            throw "provider changed after preflight. Nothing modified."
        }
        if ((Sha256 $Config) -ne $ConfigHash) {
            throw "openclaw.json changed after preflight. Nothing modified."
        }
        if ((Read-SolRollover) -ne $ExpectedOldSolRollover) {
            throw "Sol rollover config changed after preflight. Nothing modified."
        }

        $MutationStarted = $true

        # Update only the requested config value via Node JSON parse/stringify.
        $ConfigPatch = @'
const fs = require("fs");
const file = process.argv[2];
const expected = Number(process.argv[3]);
const target = Number(process.argv[4]);

const json = JSON.parse(fs.readFileSync(file, "utf8"));
const continuity =
  json?.plugins?.entries?.["forge-discord-monitor"]?.config?.continuity;

if (!continuity || typeof continuity !== "object" || Array.isArray(continuity)) {
  throw new Error("forge-discord-monitor continuity config not found");
}
if (continuity.solRolloverTokens !== expected) {
  throw new Error(
    `solRolloverTokens changed before mutation: expected ${expected}, got ${continuity.solRolloverTokens}`
  );
}

continuity.solRolloverTokens = target;
fs.writeFileSync(file, JSON.stringify(json, null, 2) + "\n", "utf8");
console.log(`solRolloverTokens ${expected} -> ${target}`);
'@

        $ConfigPatch | node - $Config $ExpectedOldSolRollover $NewSolRollover
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to update Sol rollover config."
        }

        if ((Read-SolRollover) -ne $NewSolRollover) {
            throw "Sol rollover config did not verify as 80000 after mutation."
        }

        [IO.File]::Copy($RunCandidate, $RunAttempt, $true)

        & node --check $RunAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Live 1.2.1 run-attempt failed node --check."
        }

        $Verify = [IO.File]::ReadAllText($RunAttempt)
        foreach ($Required in @($RolloverMarker, $SolBootstrapMarker, $BothDedupeMarker)) {
            if ((Count-Literal $Verify $Required) -lt 1) {
                throw "Live 1.2.1 marker verification failed: $Required"
            }
        }
        if ((Sha256 $Provider) -ne $ExpectedProviderHash) {
            throw "Provider changed during 1.2.1 apply."
        }

        openclaw gateway restart
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway restart failed after 1.2.1 apply."
        }

        if (-not (Wait-GatewayHealthy -TimeoutSeconds 120 -DelaySeconds 5)) {
            throw "Gateway did not become RPC-healthy within 120 seconds after 1.2.1 apply."
        }
    }
    catch {
        if ($MutationStarted) {
            Write-Host ""
            Write-Host "1.2.1 APPLY FAILED - restoring exact 1.2.0 run + pre-change config." -ForegroundColor Red

            [IO.File]::Copy($RunBackup, $RunAttempt, $true)
            [IO.File]::Copy($ConfigBackup, $Config, $true)

            if ((Sha256 $RunAttempt) -ne $ExpectedRunHash) {
                throw "Automatic rollback failed to restore 1.2.0 run-attempt SHA."
            }
            if ((Sha256 $Config) -ne $ConfigHash) {
                throw "Automatic rollback failed to restore pre-1.2.1 config SHA."
            }

            try {
                openclaw gateway restart | Out-Host
                [void](Wait-GatewayHealthy -TimeoutSeconds 120 -DelaySeconds 5)
            } catch {}
        }
        throw
    }

    Write-Host ""
    Write-Host "PASS - FORGE 1.2.1 SOL ROLLING IS LIVE." -ForegroundColor Green
    Write-Host "Run SHA:        $(Sha256 $RunAttempt)"
    Write-Host "Provider SHA:   $(Sha256 $Provider)"
    Write-Host "Config SHA:     $(Sha256 $Config)"
    Write-Host "Sol rollover:   $(Read-SolRollover)"
    Write-Host "Stage:          $StageDir"
    Write-Host ""
    Write-Host "ROLLBACK COMMAND:" -ForegroundColor Yellow
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
    Write-Host ""
    Write-Host "Acceptance:"
    Write-Host "  1. Send one Sol-routed canary. The existing ~128k Sol should answer it."
    Write-Host "  2. Because that completed turn is already above 80k, it should arm clean rollover."
    Write-Host "  3. Send a second Sol-routed message."
    Write-Host "  4. That second message should land on a NEW Sol native thread with ~30k canon bootstrap."
    Write-Host "  5. Ask for the canary to prove pre-rollover continuity."
    Write-Host "  6. One more Sol turn should show strong warm cache reuse on the new thread."
}