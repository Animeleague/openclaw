# Forge / AL-Kun Room Context Native additionalContext - V3
# 2026-09-18
#
# Purpose:
# - Keep the already-proven Forge last-10 retrieval unchanged.
# - Keep transient room context out of native user history.
# - Stop routing Forge transient context through collaboration/developer instructions.
# - Deliver it through Codex turn/start.additionalContext as bounded untrusted chunks.
# - Preserve existing additionalContext entries such as current sender metadata.
# - Patch only the active Codex run-attempt bundle.
# - One gateway restart, only after staged validation passes.

& {
    $ErrorActionPreference = "Stop"

    $projectDist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stageDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "forge-room-additional-context-stage-$stamp"

    if (-not (Test-Path -LiteralPath $projectDist)) {
        throw "Active Codex project dist not found: $projectDist"
    }

    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

    Write-Host ""
    Write-Host "=== 1. LOCATE CURRENT LIVE V5 BUNDLE ===" -ForegroundColor Cyan

    $candidates = @()
    Get-ChildItem -LiteralPath $projectDist -Filter "run-attempt-*.js" -File | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        if (
            $text.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4") -and
            (
                $text.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5") -or
                $text.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6")
            )
        ) {
            $candidates += $_.FullName
        }
    }

    if ($candidates.Count -ne 1) {
        Write-Host "Candidates found: $($candidates.Count)" -ForegroundColor Yellow
        $candidates | ForEach-Object { Write-Host "  $_" }
        throw "Expected exactly one active Forge transient-context Codex bundle."
    }

    $runAttempt = $candidates[0]
    $liveText = [System.IO.File]::ReadAllText($runAttempt)

    Write-Host "Selected:"
    Write-Host "  $runAttempt"

    if ($liveText.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6")) {
        Write-Host ""
        Write-Host "V6 additionalContext patch is already present. No changes or restart performed." -ForegroundColor Green
        return
    }

    if (-not $liveText.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5")) {
        throw "Current live bundle is neither expected V5 nor already-patched V6."
    }

    $stagedRunAttempt = Join-Path $stageDir ([System.IO.Path]::GetFileName($runAttempt))
    Copy-Item -LiteralPath $runAttempt -Destination $stagedRunAttempt -Force

    Write-Host ""
    Write-Host "=== 2. STAGE STRUCTURAL V6 PATCH ===" -ForegroundColor Cyan

    @'
const fs = require("fs");

const file = process.argv[2];
if (!file) throw new Error("staged run-attempt path missing");

let text = fs.readFileSync(file, "utf8");

const V4 = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4";
const V5 = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5";
const V6 = "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6";
const anchor = "codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));";

if (!text.includes(V4)) throw new Error("V4 transient carrier marker missing");
if (!text.includes(V5)) throw new Error("Expected live V5 developer-tail marker missing");
if (text.includes(V6)) throw new Error("V6 marker unexpectedly already present in staged V5 input");

function removeContainingIfBlock(source, needle, header) {
  const needleIndex = source.indexOf(needle);
  if (needleIndex < 0) throw new Error("Could not locate block needle: " + needle);
  const start = source.lastIndexOf(header, needleIndex);
  if (start < 0) throw new Error("Could not locate containing if header for: " + needle);
  const open = source.indexOf("{", start);
  if (open < 0 || open > needleIndex) throw new Error("Could not locate opening brace for: " + needle);

  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(0, start) + source.slice(index + 1);
      }
    }
  }
  throw new Error("Could not locate closing brace for: " + needle);
}

const returnPattern =
  /return\s*\{\s*promptText:\s*durablePromptText,\s*developerInstructions\s*\};/gu;
const returnMatches = [...text.matchAll(returnPattern)];
if (returnMatches.length !== 1) {
  throw new Error("Expected exactly one V4 carrier return block; found " + returnMatches.length);
}
text = text.replace(
  returnPattern,
  "return {\n                        promptText: durablePromptText,\n                        developerInstructions,\n                        transientText\n                };"
);

text = removeContainingIfBlock(
  text,
  V5,
  "if (forgeTransientRuntimeCarrierV4 && turnStartParams.collaborationMode?.settings)"
);

text = removeContainingIfBlock(
  text,
  "const forgeNativeInputTextTailV5",
  "if (forgeTransientRuntimeCarrierV4)"
);

const v4Index = text.indexOf(V4);
let anchorIndex = text.indexOf(anchor, v4Index);
if (anchorIndex < 0) throw new Error("Could not find turn/start payload anchor after V4 carrier");

const mutation = [
  "/* " + V6,
  " * Deliver current-turn Forge/OpenClaw transient reference data through",
  " * Codex native additionalContext. Keep it out of user history and",
  " * collaboration/developer instructions.",
  " */",
  "if (forgeTransientRuntimeCarrierV4) {",
  "        const forgeAdditionalContextV6 = {};",
  "        let forgeChunkV6 = \"\";",
  "        let forgeChunkBytesV6 = 0;",
  "        let forgeChunkIndexV6 = 0;",
  "        const flushForgeChunkV6 = () => {",
  "                if (!forgeChunkV6) return;",
  "                const key = \"forge_current_turn_context_\" + String(forgeChunkIndexV6).padStart(4, \"0\");",
  "                forgeAdditionalContextV6[key] = { kind: \"untrusted\", value: forgeChunkV6 };",
  "                forgeChunkIndexV6 += 1;",
  "                forgeChunkV6 = \"\";",
  "                forgeChunkBytesV6 = 0;",
  "        };",
  "        for (const symbol of forgeTransientRuntimeCarrierV4.transientText) {",
  "                const symbolBytes = Buffer.byteLength(symbol, \"utf8\");",
  "                if (forgeChunkV6 && forgeChunkBytesV6 + symbolBytes > 900) flushForgeChunkV6();",
  "                forgeChunkV6 += symbol;",
  "                forgeChunkBytesV6 += symbolBytes;",
  "        }",
  "        flushForgeChunkV6();",
  "        turnStartParams.additionalContext = {",
  "                ...(turnStartParams.additionalContext ?? {}),",
  "                ...forgeAdditionalContextV6",
  "        };",
  "}",
  ""
].join("\n");

text = text.slice(0, anchorIndex) + mutation + text.slice(anchorIndex);

anchorIndex = text.indexOf(anchor, v4Index);
if (anchorIndex < 0) throw new Error("Could not re-find payload anchor after V6 mutation");

const diagnostic = [
  "",
  "if (forgeTransientRuntimeCarrierV4) {",
  "        const forgeNativeInputTextV6 = JSON.stringify(turnStartParams.input);",
  "        const forgeDeveloperInstructionsV6 =",
  "                turnStartParams.collaborationMode?.settings?.developer_instructions ?? \"\";",
  "        const forgeAdditionalEntriesV6 = Object.entries(turnStartParams.additionalContext ?? {})",
  "                .filter(([key]) => key.startsWith(\"forge_current_turn_context_\"))",
  "                .sort(([left], [right]) => left.localeCompare(right));",
  "        const forgeAdditionalTextV6 = forgeAdditionalEntriesV6",
  "                .map(([, entry]) => entry.value)",
  "                .join(\"\");",
  "        embeddedAgentLog.info(\"forge transient runtime context turn-start placement\", {",
  "                runId: params.runId,",
  "                nativeInputHasRoomMarker: forgeNativeInputTextV6.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
  "                developerHasRoomMarker: forgeDeveloperInstructionsV6.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
  "                additionalContextHasRoomMarker: forgeAdditionalTextV6.includes(\"[FORGE_LIVE_CHANNEL_30_BEGIN]\"),",
  "                additionalContextChunkCount: forgeAdditionalEntriesV6.length,",
  "                nativeInputChars: forgeNativeInputTextV6.length,",
  "                developerInstructionChars: forgeDeveloperInstructionsV6.length,",
  "                additionalContextChars: forgeAdditionalTextV6.length",
  "        });",
  "}"
].join("\n");

text =
  text.slice(0, anchorIndex + anchor.length) +
  diagnostic +
  text.slice(anchorIndex + anchor.length);

if ((text.match(/FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6/g) ?? []).length !== 1) {
  throw new Error("V6 marker count is not exactly one");
}
if (text.includes(V5)) throw new Error("Old V5 developer-tail marker is still present");
if (text.includes("const forgeNativeInputTextTailV5")) throw new Error("Old V5 diagnostic is still present");
if (
  text.includes(
    "turnStartParams.collaborationMode.settings.developer_instructions = joinPresentSections("
  )
) {
  throw new Error("Old developer-instruction mutation is still present");
}
if (!text.includes("transientText\n                };")) {
  throw new Error("V4 carrier does not expose transientText to V6");
}
if (!text.includes("turnStartParams.additionalContext = {")) {
  throw new Error("V6 additionalContext mutation missing");
}
if (!text.includes("additionalContextHasRoomMarker")) {
  throw new Error("V6 additionalContext diagnostic missing");
}

fs.writeFileSync(file, text, "utf8");
'@ | node - $stagedRunAttempt

    if ($LASTEXITCODE -ne 0) {
        throw "V6 staged patch failed. Live system untouched."
    }

    & node --check $stagedRunAttempt
    if ($LASTEXITCODE -ne 0) {
        throw "V6 staged bundle failed node --check. Live system untouched."
    }

    $stagedText = [System.IO.File]::ReadAllText($stagedRunAttempt)
    foreach ($required in @(
        "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6",
        "turnStartParams.additionalContext = {",
        "additionalContextHasRoomMarker",
        "forge_current_turn_context_"
    )) {
        if (-not $stagedText.Contains($required)) {
            throw "Staged V6 validation missing required structure: $required"
        }
    }
    if ($stagedText.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5")) {
        throw "Staged V6 still contains V5 developer-tail marker."
    }

    Write-Host ""
    Write-Host "PREDEPLOY PASS" -ForegroundColor Green
    Write-Host "  Active V5 bundle identified"
    Write-Host "  V5 developer-tail routing removed in stage"
    Write-Host "  V6 native additionalContext routing added"
    Write-Host "  Existing additionalContext entries preserved"
    Write-Host "  Staged bundle passed node --check"
    Write-Host ""
    Write-Host "No live file has changed and no restart has happened yet." -ForegroundColor Yellow

    Write-Host ""
    Write-Host "=== 3. INSTALL VALIDATED V6 BUNDLE ===" -ForegroundColor Cyan

    $backup = "$runAttempt.pre-forge-room-additional-context-v6-$stamp.bak"
    Copy-Item -LiteralPath $runAttempt -Destination $backup -Force
    Copy-Item -LiteralPath $stagedRunAttempt -Destination $runAttempt -Force

    & node --check $runAttempt
    if ($LASTEXITCODE -ne 0) {
        Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
        throw "Live V6 bundle failed node --check after copy; backup restored. Gateway NOT restarted."
    }

    $verify = [System.IO.File]::ReadAllText($runAttempt)
    if (-not $verify.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_ADDITIONAL_V6")) {
        Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
        throw "Live V6 marker missing after copy; backup restored. Gateway NOT restarted."
    }
    if ($verify.Contains("FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_TAIL_V5")) {
        Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
        throw "Live V5 marker still present after copy; backup restored. Gateway NOT restarted."
    }

    Write-Host ""
    Write-Host "=== 4. SINGLE GATEWAY RESTART ===" -ForegroundColor Cyan
    & openclaw gateway restart
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway restart command failed. Backup retained at: $backup"
    }

    & openclaw gateway status --deep --require-rpc
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway did not pass deep RPC health check."
    }

    Write-Host ""
    Write-Host "PASS - Forge room context now routes through native additionalContext V6." -ForegroundColor Green
    Write-Host ""
    Write-Host "Live Codex backup:"
    Write-Host "  $backup"
    Write-Host ""
    Write-Host "EXPECTED TURN-START DIAGNOSTIC:"
    Write-Host "  nativeInputHasRoomMarker: false"
    Write-Host "  developerHasRoomMarker: false"
    Write-Host "  additionalContextHasRoomMarker: true"
    Write-Host "  additionalContextChunkCount: > 0"
}
