# Forge Stage 2 Codex native delta bridge - V2
# Live-proven 2026-09-15
# Marker: FORGE_CODEX_NATIVE_DELTA_V1
#
# Fail-closed recovery installer for the exact Stage 1 live bank.
# Does not restart Gateway or alter thread-lifecycle.

& {
    $ErrorActionPreference = "Stop"

    $projectDist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
    $expectedStage1Sha = "0EB6C786C7C6AE91E4DBAB882364BC7AC7BEF01C72DC22E1FBB19452E641406C"
    $marker = "FORGE_CODEX_NATIVE_DELTA_V1"

    if (-not (Test-Path -LiteralPath $projectDist)) {
        throw "Active Codex project dist not found: $projectDist"
    }

    $runAttempt = @(
        rg -l --glob "run-attempt-*.js" "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3" $projectDist 2>$null
    ) | Select-Object -First 1

    if (-not $runAttempt) {
        throw "Could not locate active run-attempt bundle."
    }

    $existing = [System.IO.File]::ReadAllText($runAttempt)

    if ($existing.Contains($marker)) {
        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Existing Stage 2 bundle fails node --check."
        }

        Write-Host ""
        Write-Host "PASS - existing Stage 2 Codex bridge is present and syntax-valid." -ForegroundColor Green
        Write-Host "Run attempt: $runAttempt"
        Write-Host "SHA256:"
        (Get-FileHash -LiteralPath $runAttempt -Algorithm SHA256).Hash
        return
    }

    $actualSha = (Get-FileHash -LiteralPath $runAttempt -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualSha -ne $expectedStage1Sha) {
        throw "Protected Stage 1 SHA mismatch. Expected $expectedStage1Sha, got $actualSha. Refusing to guess."
    }

    foreach ($required in @(
        "FORGE_CODEX_NATIVE_ROLLOVER_BOOTSTRAP_V4",
        "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3",
        "FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V4",
        "forgePostTurnNativeTokensV3 >= 120_000"
    )) {
        if (-not $existing.Contains($required)) {
            throw "Required active Codex marker missing: $required"
        }
    }

    function Write-NoBom([string]$Path, [string]$Text) {
        [System.IO.File]::WriteAllText(
            $Path,
            $Text,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }

    $anchorPattern = '(?m)^(?<indent>[ \t]*)rateLimitsRevisionBeforeLastTurnStart = readCodexRateLimitsRevision\(client\);\r?\n(?<indent2>[ \t]*)activeTurnRoute\.armTurn\(\);'
    $matches = [regex]::Matches($existing, $anchorPattern)

    if ($matches.Count -ne 1) {
        throw "Compiled turn-start anchor occurred $($matches.Count) times; expected exactly once."
    }

    $match = $matches[0]
    $indent = $match.Groups["indent"].Value
    $indent2 = $match.Groups["indent2"].Value

    if ($indent -ne $indent2) {
        throw "Compiled turn-start anchor indentation changed unexpectedly."
    }

    $nl = [Environment]::NewLine

    $inlineRaw = @'
 // FORGE_CODEX_NATIVE_DELTA_V1
 // Missed completed public Sol exchanges become real Luna native chronology once.
 const forgeNativeDeltaBridgeV1 = globalThis[Symbol.for("forge.codex-native-delta.v1")];

 if ((params.modelId ?? "").trim().toLowerCase().split("/").at(-1) === "gpt-5.6-luna" && forgeNativeDeltaBridgeV1) {
     if (!(forgeNativeDeltaBridgeV1.pendingRuns instanceof Map) ||
         !(forgeNativeDeltaBridgeV1.confirmations instanceof Map) ||
         !(forgeNativeDeltaBridgeV1.deliveredByThread instanceof Map)) {
         throw new Error("Forge native delta bridge shape is invalid; refusing Luna turn.");
     }

     const forgeNativeDeltaRawV1 = forgeNativeDeltaBridgeV1.pendingRuns.get(params.runId);

     if (forgeNativeDeltaRawV1 !== void 0) {
         const forgeNativeDeltaNowV1 = Date.now();
         const forgeNativeDeltaOldestV1 = forgeNativeDeltaNowV1 - 2 * 60 * 60 * 1e3;

         if (!forgeNativeDeltaRawV1 ||
             typeof forgeNativeDeltaRawV1 !== "object" ||
             forgeNativeDeltaRawV1.version !== 1 ||
             forgeNativeDeltaRawV1.scope !== "public-discord" ||
             forgeNativeDeltaRawV1.runId !== params.runId ||
             typeof forgeNativeDeltaRawV1.publishedAt !== "number" ||
             forgeNativeDeltaRawV1.publishedAt < forgeNativeDeltaOldestV1 ||
             !Array.isArray(forgeNativeDeltaRawV1.exchanges) ||
             !Array.isArray(forgeNativeDeltaRawV1.acknowledgeIds) ||
             forgeNativeDeltaRawV1.exchanges.length > 30 ||
             forgeNativeDeltaRawV1.acknowledgeIds.length > 256) {
             throw new Error("Forge native delta payload failed validation; refusing Luna turn.");
         }

         const forgeNativeDeltaSeenIdsV1 = new Set();

         for (const forgeNativeDeltaExchangeV1 of forgeNativeDeltaRawV1.exchanges) {
             if (!forgeNativeDeltaExchangeV1 ||
                 typeof forgeNativeDeltaExchangeV1 !== "object" ||
                 forgeNativeDeltaExchangeV1.visibility !== "public" ||
                 typeof forgeNativeDeltaExchangeV1.id !== "string" ||
                 forgeNativeDeltaExchangeV1.id.length === 0 ||
                 forgeNativeDeltaSeenIdsV1.has(forgeNativeDeltaExchangeV1.id) ||
                 typeof forgeNativeDeltaExchangeV1.timestamp !== "number" ||
                 typeof forgeNativeDeltaExchangeV1.channelId !== "string" ||
                 forgeNativeDeltaExchangeV1.channelId.length === 0 ||
                 typeof forgeNativeDeltaExchangeV1.userText !== "string" ||
                 typeof forgeNativeDeltaExchangeV1.assistantText !== "string" ||
                 (forgeNativeDeltaExchangeV1.userId !== void 0 && typeof forgeNativeDeltaExchangeV1.userId !== "string") ||
                 (forgeNativeDeltaExchangeV1.userName !== void 0 && typeof forgeNativeDeltaExchangeV1.userName !== "string") ||
                 (forgeNativeDeltaExchangeV1.messageId !== void 0 && typeof forgeNativeDeltaExchangeV1.messageId !== "string")) {
                 throw new Error("Forge native delta exchange failed validation; refusing Luna turn.");
             }

             forgeNativeDeltaSeenIdsV1.add(forgeNativeDeltaExchangeV1.id);
         }

         if (!forgeNativeDeltaRawV1.acknowledgeIds.every(
             (forgeNativeDeltaIdV1) =>
                 typeof forgeNativeDeltaIdV1 === "string" &&
                 forgeNativeDeltaIdV1.length > 0
         )) {
             throw new Error("Forge native delta acknowledgement IDs failed validation; refusing Luna turn.");
         }

         let forgeNativeDeltaDeliveredV1 =
             forgeNativeDeltaBridgeV1.deliveredByThread.get(thread.threadId);

         if (!(forgeNativeDeltaDeliveredV1 instanceof Map)) {
             forgeNativeDeltaDeliveredV1 = new Map();
             forgeNativeDeltaBridgeV1.deliveredByThread.set(
                 thread.threadId,
                 forgeNativeDeltaDeliveredV1
             );
         }

         for (const [forgeNativeDeltaDeliveredIdV1, forgeNativeDeltaDeliveredAtV1]
             of forgeNativeDeltaDeliveredV1) {
             if (typeof forgeNativeDeltaDeliveredAtV1 !== "number" ||
                 forgeNativeDeltaDeliveredAtV1 < forgeNativeDeltaOldestV1) {
                 forgeNativeDeltaDeliveredV1.delete(forgeNativeDeltaDeliveredIdV1);
             }
         }

         const forgeNativeDeltaFreshV1 =
             forgeNativeDeltaRawV1.exchanges.filter(
                 (forgeNativeDeltaExchangeV1) =>
                     !forgeNativeDeltaDeliveredV1.has(forgeNativeDeltaExchangeV1.id)
             );

         if (forgeNativeDeltaFreshV1.length > 0) {
             const forgeNativeDeltaItemsV1 =
                 forgeNativeDeltaFreshV1.flatMap((forgeNativeDeltaExchangeV1) => {
                     const forgeNativeDeltaAuthorV1 =
                         forgeNativeDeltaExchangeV1.userName
                             ? forgeNativeDeltaExchangeV1.userName +
                               (forgeNativeDeltaExchangeV1.userId
                                   ? " (" + forgeNativeDeltaExchangeV1.userId + ")"
                                   : "")
                             : (forgeNativeDeltaExchangeV1.userId ?? "unknown user");

                     const forgeNativeDeltaMetadataV1 = [
                         new Date(forgeNativeDeltaExchangeV1.timestamp).toISOString(),
                         "public channel " + forgeNativeDeltaExchangeV1.channelId,
                         "user " + forgeNativeDeltaAuthorV1,
                         forgeNativeDeltaExchangeV1.messageId
                             ? "message " + forgeNativeDeltaExchangeV1.messageId
                             : void 0,
                         "continuity-id " + forgeNativeDeltaExchangeV1.id
                     ].filter(Boolean).join(" | ");

                     return [
                         {
                             type: "message",
                             role: "user",
                             content: [{
                                 type: "input_text",
                                 text:
                                     "[Missed completed Discord exchange | " +
                                     forgeNativeDeltaMetadataV1 +
                                     "]\n" +
                                     forgeNativeDeltaExchangeV1.userText
                             }]
                         },
                         {
                             type: "message",
                             role: "assistant",
                             content: [{
                                 type: "output_text",
                                 text:
                                     "[Completed Forge reply | continuity-id " +
                                     forgeNativeDeltaExchangeV1.id +
                                     "]\n" +
                                     forgeNativeDeltaExchangeV1.assistantText
                             }]
                         }
                     ];
                 });

             await client.request(
                 "thread/inject_items",
                 {
                     threadId: thread.threadId,
                     items: forgeNativeDeltaItemsV1
                 },
                 {
                     timeoutMs: params.timeoutMs,
                     signal: runAbortController.signal
                 }
             );

             const forgeNativeDeltaInjectedAtV1 = Date.now();

             for (const forgeNativeDeltaExchangeV1 of forgeNativeDeltaFreshV1) {
                 forgeNativeDeltaDeliveredV1.set(
                     forgeNativeDeltaExchangeV1.id,
                     forgeNativeDeltaInjectedAtV1
                 );
             }
         }

         forgeNativeDeltaBridgeV1.pendingRuns.delete(params.runId);

         forgeNativeDeltaBridgeV1.confirmations.set(params.runId, {
             version: 1,
             scope: "public-discord",
             runId: params.runId,
             threadId: thread.threadId,
             acknowledgeIds: [...forgeNativeDeltaRawV1.acknowledgeIds],
             injectedExchangeIds:
                 forgeNativeDeltaRawV1.exchanges.map(
                     (forgeNativeDeltaExchangeV1) =>
                         forgeNativeDeltaExchangeV1.id
                 ),
             injectedAt: Date.now()
         });

         while (forgeNativeDeltaBridgeV1.confirmations.size > 512) {
             const forgeNativeDeltaFirstConfirmationV1 =
                 forgeNativeDeltaBridgeV1.confirmations.keys().next().value;

             if (forgeNativeDeltaFirstConfirmationV1 === void 0) break;

             forgeNativeDeltaBridgeV1.confirmations.delete(
                 forgeNativeDeltaFirstConfirmationV1
             );
         }
     }
 }
'@

    $inlineLines = $inlineRaw -split '\r?\n'
    $inlineIndented = @(
        foreach ($line in $inlineLines) {
            if ($line.Length -gt 0) {
                $indent + $line.Substring(1)
            }
            else {
                ""
            }
        }
    ) -join $nl

    $replacement =
        $indent + 'rateLimitsRevisionBeforeLastTurnStart = readCodexRateLimitsRevision(client);' +
        $nl +
        $inlineIndented +
        $nl +
        $indent + 'activeTurnRoute.armTurn();'

    $patched =
        $existing.Substring(0, $match.Index) +
        $replacement +
        $existing.Substring($match.Index + $match.Length)

    if (([regex]::Matches($patched, [regex]::Escape($marker))).Count -ne 1) {
        throw "Stage 2 marker count after patch is not exactly one."
    }

    if (-not $patched.Contains('client.request("thread/inject_items"')) {
        throw "thread/inject_items request missing after patch."
    }

    if (-not $patched.Contains('client.request("turn/start", turnStartParams')) {
        throw "Original turn/start call disappeared during patch."
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$runAttempt.pre-stage2-native-delta-v2-$stamp.bak"

    Copy-Item -LiteralPath $runAttempt -Destination $backup -Force

    try {
        Write-NoBom $runAttempt $patched

        & node --check $runAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Patched run-attempt bundle failed node --check."
        }

        $verify = [System.IO.File]::ReadAllText($runAttempt)

        if (-not $verify.Contains($marker)) {
            throw "Stage 2 marker missing after write."
        }

        if (-not $verify.Contains('client.request("turn/start", turnStartParams')) {
            throw "turn/start validation failed after write."
        }

        Write-Host ""
        Write-Host "PASS - Forge Stage 2 Codex native delta bridge V2 installed." -ForegroundColor Green
        Write-Host "Run attempt: $runAttempt"
        Write-Host "Backup:      $backup"
        Write-Host ""
        Write-Host "Old SHA256:"
        Write-Host $actualSha
        Write-Host "New SHA256:"
        (Get-FileHash -LiteralPath $runAttempt -Algorithm SHA256).Hash
        Write-Host ""
        Write-Host "Gateway has NOT been restarted." -ForegroundColor Yellow
    }
    catch {
        Copy-Item -LiteralPath $backup -Destination $runAttempt -Force
        throw
    }
}
