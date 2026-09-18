# Forge / AL-Kun Room Context Transient Tail - V1
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
# Live intent:
# - Same last-10 human/non-bot room lookup for Sol and Luna.
# - Exactly one room snapshot.
# - Keep Forge room context OUT of native user history.
# - Route it through turn-scoped developer instructions.
# - Place it after workspace/memory/skills for strongest recency.
# - Preserve native history/cache shape and avoid ~1k/turn staircasing.
# - One gateway restart, only after all preflight checks pass.

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

    $runAttempt = @(
        rg -l --glob "run-attempt-*.js" "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4" $projectDist 2>$null
    ) | Select-Object -First 1

    if (-not $runAttempt) {
        throw "Could not locate active Codex run-attempt bundle with V4 transient-context marker."
    }

    $liveText = [System.IO.File]::ReadAllText($runAttempt)

    foreach ($required in @(
        "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4",
        "FORGE_CROSS_MODEL_NATIVE_DELTA_V1",
        "FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1"
    )) {
        if (-not $liveText.Contains($required)) {
            throw "Required live Codex marker missing: $required"
        }
    }

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

const marker = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5";

if (!text.includes("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4")) {
  throw new Error("V4 transient runtime context marker missing");
}

if (!text.includes(marker)) {
  const oldPattern =
    /(?<indent>[ \t]*)turnScopedDeveloperInstructions:\s*joinPresentSections\(workspaceBootstrapContext\.turnScopedDeveloperInstructions,\s*forgeTransientRuntimeCarrierV4\?\.developerInstructions\),\s*\r?\n[ \t]*skillsCollaborationInstructions,\s*\r?\n[ \t]*memoryCollaborationInstructions:\s*workspaceBootstrapContext\.memoryCollaborationInstructions,/u;

  const matches = [...text.matchAll(new RegExp(oldPattern.source, "gu"))];
  if (matches.length !== 1) {
    throw new Error(
      "Expected exactly one V4 turn-scoped ordering block; found " + matches.length
    );
  }

  const indent = matches[0].groups?.indent ?? "";
  const replacement = [
    indent + "turnScopedDeveloperInstructions: workspaceBootstrapContext.turnScopedDeveloperInstructions,",
    indent + "skillsCollaborationInstructions: joinPresentSections(",
    indent + "  skillsCollaborationInstructions,",
    indent + "  forgeTransientRuntimeCarrierV4?.developerInstructions",
    indent + "), // " + marker,
    indent + "memoryCollaborationInstructions: workspaceBootstrapContext.memoryCollaborationInstructions,"
  ].join("\n");

  text = text.replace(oldPattern, replacement);

  const anchor =
    "codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));";
  const v4Index = text.indexOf("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4");
  const anchorIndex = text.indexOf(anchor, v4Index);
  if (anchorIndex < 0) {
    throw new Error("Could not find turn-start diagnostic insertion anchor after V4 carrier");
  }

  const diagnostic = [
    "",
    "        if (forgeTransientRuntimeCarrierV4) {",
    "                const forgeNativeInputTextTailV5 = JSON.stringify(turnStartParams.input);",
    "                const forgeDeveloperInstructionsTailV5 =",
    "                        turnStartParams.collaborationMode?.settings?.developer_instructions ?? \"\";",
    "                embeddedAgentLog.info(\"forge transient runtime context turn-start placement\", {",
    "                        runId: params.runId,",
    "                        nativeInputHasRoomMarker: forgeNativeInputTextTailV5.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
    "                        developerHasRoomMarker: forgeDeveloperInstructionsTailV5.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
    "                        developerEndsWithForgeContext: forgeDeveloperInstructionsTailV5.endsWith(\"</forge_current_turn_context>\"),",
    "                        nativeInputChars: forgeNativeInputTextTailV5.length,",
    "                        developerInstructionChars: forgeDeveloperInstructionsTailV5.length",
    "                });",
    "        }"
  ].join("\n");

  text =
    text.slice(0, anchorIndex + anchor.length) +
    diagnostic +
    text.slice(anchorIndex + anchor.length);
}

if ((text.match(/FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5/g) ?? []).length !== 1) {
  throw new Error("V5 tail marker count is not exactly one");
}

if (
  text.includes(
    "turnScopedDeveloperInstructions: joinPresentSections(workspaceBootstrapContext.turnScopedDeveloperInstructions, forgeTransientRuntimeCarrierV4?.developerInstructions)"
  )
) {
  throw new Error("Old V4 early-placement expression is still present");
}

if (
  !text.includes(
    "skillsCollaborationInstructions: joinPresentSections("
  ) ||
  !text.includes("forgeTransientRuntimeCarrierV4?.developerInstructions")
) {
  throw new Error("Late transient developer placement is missing");
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

        Write-Host ""
        Write-Host "PREDEPLOY PASS" -ForegroundColor Green
        Write-Host "  Forge full checks passed"
        Write-Host "  Forge package built from $forgeCommit"
        Write-Host "  Codex V5 transient-tail patch staged and syntax-valid"
        Write-Host "  Canonical OpenClaw source commit: $openclawSourceCommit"
        Write-Host ""
        Write-Host "No gateway restart has happened yet." -ForegroundColor Yellow

        # ----------------------------------------------------------
        # Live install only begins after every preflight above passed.
        # ----------------------------------------------------------

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

        $backup = "$runAttempt.pre-forge-room-transient-tail-v1-$stamp.bak"
        Copy-Item -LiteralPath $runAttempt -Destination $backup -Force
        Copy-Item -LiteralPath $stagedRunAttempt -Destination $runAttempt -Force

        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
            throw "Live Codex file failed node --check after copy; restored backup. Gateway NOT restarted."
        }

        $verify = [System.IO.File]::ReadAllText($runAttempt)
        if (-not $verify.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5")) {
            Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
            throw "Live Codex V5 marker missing after copy; restored backup. Gateway NOT restarted."
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
        Write-Host "PASS - Forge room-context transient-tail V1 deployed." -ForegroundColor Green
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
        Write-Host "  - Forge transient block is at the developer tail"
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
