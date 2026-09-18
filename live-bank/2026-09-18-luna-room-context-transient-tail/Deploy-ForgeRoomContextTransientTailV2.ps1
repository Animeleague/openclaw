# Forge / AL-Kun Room Context Transient Tail - V2
# 2026-09-18
#
# Canonical source:
#   forge-discord-gateway:
#     branch fix/2026-09-18-luna-room-context-transient-tail
#     commit c14316a8b8282ab40401206bc5af40c13e525434
#   openclaw:
#     branch fix/2026-09-18-luna-room-context-transient-tail
#     source commit 4d6c0641696483b419d6678f490d1c191be3835c
#
# V2 changes from V1:
# - Removes unrelated continuity-marker prechecks.
# - Selects the active Codex bundle by the exact V4 transient-context code shape.
# - Removes Forge transient context from the early turnScopedDeveloperInstructions slot.
# - Appends it directly to the fully-built turnStart developer_instructions, guaranteeing tail position.
# - Keeps native user input clean.
# - One gateway restart only after every preflight passes.

& {
    $ErrorActionPreference = "Stop"

    $desktop = [Environment]::GetFolderPath("Desktop")
    $forgeRepo = Join-Path $desktop "forge-discord-monitor-v1.1.3"
    $forgeBranch = "fix/2026-09-18-luna-room-context-transient-tail"
    $forgeCommit = "c14316a8b8282ab40401206bc5af40c13e525434"
    $openclawSourceCommit = "4d6c0641696483b419d6678f490d1c191be3835c"

    $projectDist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $worktree = Join-Path $desktop "forge-room-tail-worktree-$stamp"
    $packDir = Join-Path $desktop "forge-room-tail-pack-$stamp"
    $stageDir = Join-Path $desktop "forge-room-tail-stage-$stamp"

    if (-not (Test-Path -LiteralPath $forgeRepo)) {
        throw "Forge monitor repo not found: $forgeRepo"
    }
    if (-not (Test-Path -LiteralPath $projectDist)) {
        throw "Active Codex project dist not found: $projectDist"
    }

    Write-Host ""
    Write-Host "=== PRECHECK: current Forge working copy is informational only ===" -ForegroundColor Cyan
    & git -C $forgeRepo status --short
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Forge repo status."
    }
    Write-Host "Existing working copy will NOT be modified."

    & git -C $forgeRepo worktree prune
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree prune failed."
    }

    Write-Host ""
    Write-Host "Fetching committed Forge fix..."
    & git -C $forgeRepo fetch origin $forgeBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Forge branch fetch failed."
    }

    & git -C $forgeRepo cat-file -e "$forgeCommit^{commit}"
    if ($LASTEXITCODE -ne 0) {
        throw "Pinned Forge commit not found after fetch: $forgeCommit"
    }

    New-Item -ItemType Directory -Force -Path $packDir | Out-Null
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

    Write-Host ""
    Write-Host "Locating exact active V4 transient-context bundle..."

    $earlyExpression = "turnScopedDeveloperInstructions: joinPresentSections(workspaceBootstrapContext.turnScopedDeveloperInstructions, forgeTransientRuntimeCarrierV4?.developerInstructions)"
    $v5Marker = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5"

    $v4Files = @()
    $structuralCandidates = @()

    Get-ChildItem -LiteralPath $projectDist -Filter "run-attempt-*.js" -File | ForEach-Object {
        $candidateText = [System.IO.File]::ReadAllText($_.FullName)
        if ($candidateText.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4")) {
            $v4Files += $_.FullName
            if ($candidateText.Contains($earlyExpression) -or $candidateText.Contains($v5Marker)) {
                $structuralCandidates += $_.FullName
            }
        }
    }

    if ($structuralCandidates.Count -ne 1) {
        Write-Host ""
        Write-Host "V4 marker files found:" -ForegroundColor Yellow
        $v4Files | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Exact structural candidates found: $($structuralCandidates.Count)" -ForegroundColor Yellow
        $structuralCandidates | ForEach-Object { Write-Host "  $_" }
        throw "Expected exactly one active Codex bundle matching the V4 transient-context structure."
    }

    $runAttempt = $structuralCandidates[0]
    $liveText = [System.IO.File]::ReadAllText($runAttempt)

    if (-not $liveText.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4")) {
        throw "Selected Codex bundle unexpectedly lacks V4 transient-context marker."
    }

    if (-not $liveText.Contains($v5Marker) -and -not $liveText.Contains($earlyExpression)) {
        throw "Selected V4 bundle does not contain the exact early transient-context expression to replace."
    }

    Write-Host "Selected Codex bundle:"
    Write-Host "  $runAttempt"

    $stagedRunAttempt = Join-Path $stageDir ([System.IO.Path]::GetFileName($runAttempt))
    Copy-Item -LiteralPath $runAttempt -Destination $stagedRunAttempt -Force

    try {
        Write-Host ""
        Write-Host "=== 1. VALIDATE FORGE MONITOR SOURCE ===" -ForegroundColor Cyan

        & git -C $forgeRepo worktree add --detach $worktree $forgeCommit
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create detached Forge worktree."
        }

        Push-Location -LiteralPath $worktree
        try {
            & npm ci
            if ($LASTEXITCODE -ne 0) {
                throw "npm ci failed. Live system untouched."
            }

            & npm run check
            if ($LASTEXITCODE -ne 0) {
                throw "Forge full test/check failed. Live system untouched."
            }

            & npm pack --pack-destination $packDir
            if ($LASTEXITCODE -ne 0) {
                throw "Forge npm pack failed. Live system untouched."
            }
        }
        finally {
            Pop-Location
        }

        $package = Get-ChildItem -LiteralPath $packDir -Filter "*.tgz" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $package) {
            throw "No tested Forge package was produced."
        }

        Write-Host ""
        Write-Host "=== 2. STAGE AND VALIDATE CODEX LIVE PATCH ===" -ForegroundColor Cyan

        @'
const fs = require("fs");

const file = process.argv[2];
if (!file) throw new Error("staged run-attempt path missing");

let text = fs.readFileSync(file, "utf8");

const v4 = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4";
const v5 = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5";
const early =
  "turnScopedDeveloperInstructions: joinPresentSections(workspaceBootstrapContext.turnScopedDeveloperInstructions, forgeTransientRuntimeCarrierV4?.developerInstructions)";

if (!text.includes(v4)) {
  throw new Error("V4 transient runtime context marker missing");
}

if (!text.includes(v5)) {
  const earlyCount = text.split(early).length - 1;
  if (earlyCount !== 1) {
    throw new Error("Expected exactly one early V4 placement expression; found " + earlyCount);
  }

  text = text.replace(
    early,
    "turnScopedDeveloperInstructions: workspaceBootstrapContext.turnScopedDeveloperInstructions"
  );

  const anchor =
    "codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));";
  const v4Index = text.indexOf(v4);
  const anchorIndex = text.indexOf(anchor, v4Index);
  if (anchorIndex < 0) {
    throw new Error("Could not find turn/start payload anchor after V4 carrier");
  }

  const tailMutation = [
    "if (forgeTransientRuntimeCarrierV4 && turnStartParams.collaborationMode?.settings) {",
    "        turnStartParams.collaborationMode.settings.developer_instructions = joinPresentSections(",
    "                turnStartParams.collaborationMode.settings.developer_instructions ?? void 0,",
    "                forgeTransientRuntimeCarrierV4.developerInstructions",
    "        ); // " + v5,
    "}",
    ""
  ].join("\n");

  text =
    text.slice(0, anchorIndex) +
    tailMutation +
    text.slice(anchorIndex);

  const diagnosticAnchor =
    "codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));";
  const diagnosticIndex = text.indexOf(diagnosticAnchor, v4Index);
  if (diagnosticIndex < 0) {
    throw new Error("Could not find diagnostic insertion anchor");
  }

  const diagnostic = [
    "",
    "if (forgeTransientRuntimeCarrierV4) {",
    "        const forgeNativeInputTextTailV5 = JSON.stringify(turnStartParams.input);",
    "        const forgeDeveloperInstructionsTailV5 =",
    "                turnStartParams.collaborationMode?.settings?.developer_instructions ?? \"\";",
    "        embeddedAgentLog.info(\"forge transient runtime context turn-start placement\", {",
    "                runId: params.runId,",
    "                nativeInputHasRoomMarker: forgeNativeInputTextTailV5.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
    "                developerHasRoomMarker: forgeDeveloperInstructionsTailV5.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
    "                developerEndsWithForgeContext: forgeDeveloperInstructionsTailV5.endsWith(\"</forge_current_turn_context>\"),",
    "                nativeInputChars: forgeNativeInputTextTailV5.length,",
    "                developerInstructionChars: forgeDeveloperInstructionsTailV5.length",
    "        });",
    "}"
  ].join("\n");

  text =
    text.slice(0, diagnosticIndex + diagnosticAnchor.length) +
    diagnostic +
    text.slice(diagnosticIndex + diagnosticAnchor.length);
}

const v5Count = (text.match(/FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5/g) ?? []).length;
if (v5Count !== 1) {
  throw new Error("V5 tail marker count is not exactly one: " + v5Count);
}

if (text.includes(early)) {
  throw new Error("Old early V4 placement expression is still present");
}

if (!text.includes("turnScopedDeveloperInstructions: workspaceBootstrapContext.turnScopedDeveloperInstructions")) {
  throw new Error("Clean turnScopedDeveloperInstructions expression missing");
}

if (!text.includes("turnStartParams.collaborationMode.settings.developer_instructions = joinPresentSections(")) {
  throw new Error("Final developer-instructions tail mutation missing");
}

if (!text.includes("forgeTransientRuntimeCarrierV4.developerInstructions")) {
  throw new Error("Forge transient developer context missing from final tail mutation");
}

if (!text.includes("forge transient runtime context turn-start placement")) {
  throw new Error("Actual turn/start placement diagnostic is missing");
}

fs.writeFileSync(file, text, "utf8");
'@ | node - $stagedRunAttempt

        if ($LASTEXITCODE -ne 0) {
            throw "Codex staged patch failed. Live system untouched."
        }

        & node --check $stagedRunAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Patched Codex staged bundle failed node --check. Live system untouched."
        }

        $stagedText = [System.IO.File]::ReadAllText($stagedRunAttempt)
        if ($stagedText.Contains($earlyExpression)) {
            throw "Staged bundle still contains the old early transient-context placement."
        }
        if (-not $stagedText.Contains($v5Marker)) {
            throw "Staged bundle is missing the V5 transient-tail marker."
        }
        if (-not $stagedText.Contains("forge transient runtime context turn-start placement")) {
            throw "Staged bundle is missing the turn/start placement diagnostic."
        }

        Write-Host ""
        Write-Host "PREDEPLOY PASS" -ForegroundColor Green
        Write-Host "  Forge full checks passed"
        Write-Host "  Forge package built from $forgeCommit"
        Write-Host "  Exact V4 Codex bundle selected by structure"
        Write-Host "  V5 transient-tail patch staged and syntax-valid"
        Write-Host "  Canonical OpenClaw source commit: $openclawSourceCommit"
        Write-Host ""
        Write-Host "No gateway restart has happened yet." -ForegroundColor Yellow

        # Live install begins only after every preflight above passed.

        Write-Host ""
        Write-Host "=== 3. INSTALL TESTED FORGE PACKAGE ===" -ForegroundColor Cyan
        & openclaw plugins install "npm-pack:$($package.FullName)" --force
        if ($LASTEXITCODE -ne 0) {
            throw "Forge plugin installation failed before Codex live patch."
        }

        & openclaw plugins enable forge-discord-monitor
        if ($LASTEXITCODE -ne 0) {
            throw "Could not enable forge-discord-monitor."
        }

        & openclaw config validate
        if ($LASTEXITCODE -ne 0) {
            throw "Config validation failed. Gateway has NOT been restarted."
        }

        Write-Host ""
        Write-Host "=== 4. INSTALL VALIDATED CODEX PATCH ===" -ForegroundColor Cyan

        $backup = "$runAttempt.pre-forge-room-transient-tail-v2-$stamp.bak"
        Copy-Item -LiteralPath $runAttempt -Destination $backup -Force
        Copy-Item -LiteralPath $stagedRunAttempt -Destination $runAttempt -Force

        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
            throw "Live Codex file failed node --check after copy; restored backup. Gateway NOT restarted."
        }

        $verify = [System.IO.File]::ReadAllText($runAttempt)
        if (-not $verify.Contains($v5Marker)) {
            Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
            throw "Live Codex V5 marker missing after copy; restored backup. Gateway NOT restarted."
        }
        if ($verify.Contains($earlyExpression)) {
            Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
            throw "Live Codex still contains old early placement; restored backup. Gateway NOT restarted."
        }

        Write-Host ""
        Write-Host "=== 5. SINGLE GATEWAY RESTART ===" -ForegroundColor Cyan
        & openclaw gateway restart
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway restart command failed. Codex backup retained at: $backup"
        }

        & openclaw gateway status --deep --require-rpc
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway did not pass deep RPC health check."
        }

        Write-Host ""
        Write-Host "PASS - Forge room-context transient-tail V2 deployed." -ForegroundColor Green
        Write-Host ""
        Write-Host "Forge commit:"
        Write-Host "  $forgeCommit"
        Write-Host "OpenClaw source commit:"
        Write-Host "  $openclawSourceCommit"
        Write-Host "Live Codex backup:"
        Write-Host "  $backup"
        Write-Host ""
        Write-Host "EXPECTED LIVE INVARIANTS:"
        Write-Host "  - Sol and Luna both receive last-10 room context"
        Write-Host "  - exactly one room snapshot"
        Write-Host "  - native user input contains zero room markers"
        Write-Host "  - turn-scoped developer instructions contain one room snapshot"
        Write-Host "  - Forge transient block is the final developer-instruction section"
        Write-Host "  - no ~1k-per-turn persistence staircase"
        Write-Host "  - existing Sol/Luna continuity and memory remain unchanged"
    }
    finally {
        if (Test-Path -LiteralPath $worktree) {
            Write-Host "Removing detached Forge worktree..."
            & git -C $forgeRepo worktree remove --force $worktree 2>$null
        }
    }
}
