# Forge Rolling Continuity V5
# 2026-09-17
# Applies:
# - explicit Forge continuity config
# - 80k configurable Sol completed-turn rollover
# - 20k configurable fresh-Sol conversation bootstrap
# - unbounded-by-count Sol -> Luna Stage 2 native delta
# - per-Luna-thread delivery ledger retained for the warm thread lifetime
#
# Requires the banked Stage 2 markers already live.

& {
    $ErrorActionPreference = "Stop"

    $cfg = "$env:USERPROFILE\.openclaw\openclaw.json"
    $projectDist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"

    if (-not (Test-Path -LiteralPath $cfg)) {
        throw "OpenClaw config not found: $cfg"
    }
    if (-not (Test-Path -LiteralPath $projectDist)) {
        throw "Active Codex dist not found: $projectDist"
    }

    $runAttempt = @(
        Get-ChildItem -LiteralPath $projectDist -File -Filter "run-attempt-*.js" |
            Where-Object {
                Select-String -LiteralPath $_.FullName -Pattern "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3" -Quiet
            }
    ) | Select-Object -First 1

    if (-not $runAttempt) {
        throw "Could not find active run-attempt bundle with Forge native hardcap marker."
    }

    $runAttempt = $runAttempt.FullName
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $cfgBackup = "$cfg.pre-rolling-continuity-v5-$stamp.bak"
    $runBackup = "$runAttempt.pre-rolling-continuity-v5-$stamp.bak"

    Copy-Item -LiteralPath $cfg -Destination $cfgBackup -Force
    Copy-Item -LiteralPath $runAttempt -Destination $runBackup -Force

    try {
        # --------------------------------------------------------------
        # 1. Make the policy explicit in openclaw.json.
        # --------------------------------------------------------------
        @'
const fs = require("fs");
const file = process.argv[2];
if (!file) throw new Error("Config path argument missing.");

const json = JSON.parse(fs.readFileSync(file, "utf8"));
const monitor =
  json?.plugins?.entries?.["forge-discord-monitor"]?.config;

if (!monitor || typeof monitor !== "object" || Array.isArray(monitor)) {
  throw new Error("forge-discord-monitor config not found.");
}

monitor.continuity = {
  ...(monitor.continuity && typeof monitor.continuity === "object"
    ? monitor.continuity
    : {}),
  solRolloverTokens: 80000,
  solFreshHistoryTokens: 20000,
  nativeJournalRetentionMs: 2592000000,
  nativeJournalMaxStoredExchanges: 10000,
  nativeDeltaMaxExchanges: 0
};

// Preserve the assistance-context hotfix.
monitor.assistanceDispatch = {
  ...(monitor.assistanceDispatch && typeof monitor.assistanceDispatch === "object"
    ? monitor.assistanceDispatch
    : {}),
  injectReasonContext: false
};

fs.writeFileSync(file, JSON.stringify(json, null, 2) + "\n", "utf8");
console.log("Configured Forge rolling continuity:", monitor.continuity);
'@ | node - $cfg

        if ($LASTEXITCODE -ne 0) {
            throw "Config update failed."
        }

        # --------------------------------------------------------------
        # 2. Patch the active compiled Codex bundle.
        # --------------------------------------------------------------
        @'
const fs = require("fs");
const file = process.argv[2];
if (!file) throw new Error("Run-attempt path argument missing.");

let text = fs.readFileSync(file, "utf8");

const replaceOnce = (from, to, label) => {
  const first = text.indexOf(from);
  if (first < 0) throw new Error(label + " anchor missing.");
  if (text.indexOf(from, first + from.length) >= 0) {
    throw new Error(label + " anchor occurred more than once.");
  }
  text = text.slice(0, first) + to + text.slice(first + from.length);
};

// Fresh Sol generations should only replay a bounded recent canon tail.
// 4 chars/token is the existing Codex projection approximation.
if (!text.includes("FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1")) {
  const freshAnchor =
`\tconst applyFreshThreadContinuityProjection = () => {
\t\tconst projection = projectContextEngineAssemblyForCodex({
\t\t\tassembledMessages: historyMessages,
\t\t\toriginalHistoryMessages: historyMessages,
\t\t\tprompt: params.prompt,
\t\t\tmaxRenderedContextChars: codexContextProjectionMaxChars
\t\t});`;

  const freshReplacement =
`\t// FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1
\tconst forgeContinuityConfigV5 = params.config?.plugins?.entries?.["forge-discord-monitor"]?.config?.continuity;
\tconst forgeFreshHistoryRawV5 = forgeContinuityConfigV5?.solFreshHistoryTokens;
\tconst forgeFreshHistoryTokensV5 =
\t\ttypeof forgeFreshHistoryRawV5 === "number" &&
\t\tNumber.isFinite(forgeFreshHistoryRawV5) &&
\t\tforgeFreshHistoryRawV5 > 0
\t\t\t? Math.floor(forgeFreshHistoryRawV5)
\t\t\t: 20_000;
\tconst forgeFreshHistoryMaxCharsV5 = Math.max(4_000, forgeFreshHistoryTokensV5 * 4);
\tconst applyFreshThreadContinuityProjection = () => {
\t\tconst projection = projectContextEngineAssemblyForCodex({
\t\t\tassembledMessages: historyMessages,
\t\t\toriginalHistoryMessages: historyMessages,
\t\t\tprompt: params.prompt,
\t\t\tmaxRenderedContextChars: Math.min(codexContextProjectionMaxChars, forgeFreshHistoryMaxCharsV5)
\t\t});`;

  replaceOnce(freshAnchor, freshReplacement, "fresh Sol history cap");
}

// Give the post-turn hardcap helper access to the same config object.
if (!text.includes("FORGE_CODEX_ROLLOVER_CONFIG_V5")) {
  const callAnchor =
`                                codexHome: appServer.start.env?.CODEX_HOME
                        });`;
  const callReplacement =
`                                codexHome: appServer.start.env?.CODEX_HOME,
                                config: params.config // FORGE_CODEX_ROLLOVER_CONFIG_V5
                        });`;
  replaceOnce(callAnchor, callReplacement, "post-turn coverage call");

  const threshold120 =
`        if (
                forgePostTurnNativeTokensV3 !== void 0 &&
                forgePostTurnNativeTokensV3 >= 120_000
        ) {`;
  const threshold60 =
`        if (
                forgePostTurnNativeTokensV3 !== void 0 &&
                forgePostTurnNativeTokensV3 >= 60_000
        ) {`;

  const thresholdReplacement =
`        const forgePostTurnHardcapRawV5 =
                params.config?.plugins?.entries?.["forge-discord-monitor"]?.config?.continuity?.solRolloverTokens;
        const forgePostTurnHardcapTokensV5 =
                typeof forgePostTurnHardcapRawV5 === "number" &&
                Number.isFinite(forgePostTurnHardcapRawV5) &&
                forgePostTurnHardcapRawV5 > 0
                        ? Math.floor(forgePostTurnHardcapRawV5)
                        : 80_000;

        if (
                forgePostTurnNativeTokensV3 !== void 0 &&
                forgePostTurnNativeTokensV3 >= forgePostTurnHardcapTokensV5
        ) {`;

  if (text.includes(threshold120)) {
    replaceOnce(threshold120, thresholdReplacement, "120k hardcap");
  } else if (text.includes(threshold60)) {
    replaceOnce(threshold60, thresholdReplacement, "60k hardcap");
  } else {
    throw new Error("Expected 60k/120k hardcap block not found.");
  }

  text = text.replace(
    /"forge native thread reached completed-turn (?:60k|120k) hardcap; fresh rollover armed"/u,
    '"forge native thread reached completed-turn configured hardcap; fresh rollover armed"'
  );
  text = text.replace(
    /hardcap: (?:60_000|120_000)/u,
    "hardcap: forgePostTurnHardcapTokensV5"
  );
}

// Stage 2 should not arbitrarily truncate Sol chronology at 30 exchanges.
if (text.includes("forgeNativeDeltaRawV1.exchanges.length > 30")) {
  text = text.replace(
    /\s*forgeNativeDeltaRawV1\.exchanges\.length > 30 \|\|\s*forgeNativeDeltaRawV1\.acknowledgeIds\.length > 256/u,
    ""
  );
}

// Retained journal + warm thread ledger means delivered IDs must not expire
// after two hours or the same Sol exchanges would be re-injected.
const deliveredCleanup =
`          for (const [forgeNativeDeltaDeliveredIdV1, forgeNativeDeltaDeliveredAtV1]
              of forgeNativeDeltaDeliveredV1) {
              if (typeof forgeNativeDeltaDeliveredAtV1 !== "number" ||
                  forgeNativeDeltaDeliveredAtV1 < forgeNativeDeltaOldestV1) {
                  forgeNativeDeltaDeliveredV1.delete(forgeNativeDeltaDeliveredIdV1);
              }
          }

`;
if (text.includes(deliveredCleanup)) {
  text = text.replace(
    deliveredCleanup,
    `          // FORGE_NATIVE_DELTA_WARM_THREAD_LEDGER_V2
          // Keep delivered IDs for this Luna native generation. A fresh Luna
          // thread gets a fresh ledger and therefore receives the retained journal.

`
  );
}

for (const marker of [
  "FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4",
  "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3",
  "FORGE_CROSS_MODEL_NATIVE_DELTA_V1",
  "FORGE_CODEX_FRESH_THREAD_HISTORY_CAP_V1",
  "FORGE_CODEX_ROLLOVER_CONFIG_V5",
  "FORGE_NATIVE_DELTA_WARM_THREAD_LEDGER_V2"
]) {
  if (!text.includes(marker)) throw new Error("Required marker missing after patch: " + marker);
}

if (text.includes("forgeNativeDeltaRawV1.exchanges.length > 30")) {
  throw new Error("Stage 2 30-exchange hard bound still present.");
}

fs.writeFileSync(file, text, "utf8");
'@ | node - $runAttempt

        if ($LASTEXITCODE -ne 0) {
            throw "Run-attempt patch failed."
        }

        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Patched run-attempt bundle failed node --check."
        }

        Write-Host ""
        Write-Host "PASS - Forge Rolling Continuity V5 staged live files." -ForegroundColor Green
        Write-Host "Config: $cfg"
        Write-Host "Run attempt: $runAttempt"
        Write-Host "Config backup: $cfgBackup"
        Write-Host "Run backup: $runBackup"
        Write-Host ""
        Write-Host "Configured policy:"
        Write-Host "  Sol rollover: 80k native tokens"
        Write-Host "  Fresh Sol recent history: 20k tokens (~80k chars)"
        Write-Host "  Native journal retention: 30 days"
        Write-Host "  Native journal max records: 10,000"
        Write-Host "  Sol -> Luna native delta count cap: NONE"
        Write-Host ""
        Write-Host "Run-attempt SHA256:"
        (Get-FileHash -LiteralPath $runAttempt -Algorithm SHA256).Hash
    }
    catch {
        Copy-Item -LiteralPath $cfgBackup -Destination $cfg -Force
        Copy-Item -LiteralPath $runBackup -Destination $runAttempt -Force
        throw
    }
}
