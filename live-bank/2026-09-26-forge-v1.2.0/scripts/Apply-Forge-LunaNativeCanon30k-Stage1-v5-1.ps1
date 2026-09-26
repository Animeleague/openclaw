# Forge Rolling Sessions - Stage 1 V5.1 Native Bootstrap
#
# Replaces the failed fresh-Luna prompt-projection experiment with native history
# injection on the already-proven pre-turn thread/inject_items path.
#
# Exact starting state:
#   run-attempt V4 SHA from 2026-09-26 native-bootstrap diagnostic
#   provider-capabilities V4 SHA from same diagnostic
#
# Behaviour:
# - only gpt-5.6-luna
# - only when native thread lifecycle.action === "started"
# - reads exactly params.sessionFile through the already-installed V4 canonical-file bypass
# - sanitization remains in the existing provider history reader
# - converts only user/assistant text into native message items
# - preserves lightweight sender/timestamp provenance when available
# - newest native bootstrap <= 120,000 rendered text chars (~30k tokens)
# - injects once before turn/start
# - warm/resumed Luna unchanged
# - Sol unchanged
# - existing bidirectional 20-item native delta unchanged
# - if an exact native-delta pair is already present in the fresh canon bootstrap,
#   it is marked delivered so it is not injected twice
# - removes the dead V3 prompt-hydration logic and restores its original projection path
#
# Safety:
# - exact SHA gates
# - exact structural anchors
# - staged candidate
# - node --check
# - byte-for-byte backup
# - one-command rollback
# - 120 second gateway health window
# - automatic rollback on failure

param(
    [switch]$PreflightOnly
)

& {
    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version Latest

    $Dist = "$env:USERPROFILE\.openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
    $RunAttempt = Join-Path $Dist "run-attempt-FUyOjGCV.js"
    $Provider = Join-Path $Dist "provider-capabilities-CDnHbmUZ.js"

    $ExpectedRunHash = "d39a4e878a0a80a95c773094b6d2e90d6edb91fe570e1550963e5280ee8bc933"
    $ExpectedProviderHash = "9f7eb3c6bdbdaba427858b94f7c4e7e57308a1bbf1ad92451aea83f70855467c"

    $V3Marker = "FORGE_LUNA_FRESH_CANON_HYDRATION_30K_STAGE1_V3"
    $V4RunMarker = "FORGE_LUNA_CANON_READ_FLAG_V4"
    $V4ProviderMarker = "FORGE_LUNA_CANON_RESOLVER_BYPASS_V4"
    $V5Marker = "FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_30K_V5"

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
                $Remaining = [Math]::Max(0, $TimeoutSeconds - [Math]::Floor($Watch.Elapsed.TotalSeconds))
                $SleepFor = [Math]::Min($DelaySeconds, $Remaining)
                if ($SleepFor -gt 0) {
                    Start-Sleep -Seconds $SleepFor
                }
            }
        }
        $Watch.Stop()
        return $false
    }

    foreach ($Path in @($RunAttempt, $Provider)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Required live bundle missing: $Path"
        }
    }

    $RunHash = Sha256 $RunAttempt
    $ProviderHash = Sha256 $Provider

    if ($RunHash -ne $ExpectedRunHash) {
        throw @"
run-attempt is not the exact V4 state proven by the native-bootstrap diagnostic.
Expected: $ExpectedRunHash
Actual:   $RunHash

Nothing changed.
"@
    }

    if ($ProviderHash -ne $ExpectedProviderHash) {
        throw @"
provider-capabilities is not the exact V4 state proven by the native-bootstrap diagnostic.
Expected: $ExpectedProviderHash
Actual:   $ProviderHash

Nothing changed.
"@
    }

    $Original = [IO.File]::ReadAllText($RunAttempt)
    $ProviderText = [IO.File]::ReadAllText($Provider)

    foreach ($Required in @(
        "FORGE_CODEX_NATIVE_DELTA_V1",
        "FORGE_CODEX_BIDIRECTIONAL_NATIVE_DELTA_V2",
        "FORGE_CODEX_DUAL_WARM_THREADS_V2_1",
        "FORGE_CODEX_MONITOR_PROJECTION_BYPASS_V1_02",
        "FORGE_CODEX_MONITOR_WARM_ROLLBACK_V1_04_FINAL5",
        $V3Marker,
        $V4RunMarker
    )) {
        if ((Count-Literal $Original $Required) -lt 1) {
            throw "Required current run marker missing: $Required"
        }
    }

    if ((Count-Literal $ProviderText $V4ProviderMarker) -ne 1) {
        throw "Required provider V4 canonical resolver bypass marker missing or duplicated."
    }

    if ($Original.Contains($V5Marker)) {
        throw "V5 native canonical bootstrap is already present. Nothing changed."
    }

    $CandidateText = $Original

    # ------------------------------------------------------------------
    # 1. Remove the failed V3 prompt-hydration prelude and restore the
    #    original fresh projection function using historyMessages.
    # ------------------------------------------------------------------
    $PromptHydrationStartNeedle =
        'const forgeFreshLunaHydrationMaxCharsStage1V3 = 30_000 * 4; // FORGE_LUNA_FRESH_CANON_HYDRATION_30K_STAGE1_V3'
    $ApplyActiveNeedle = 'const applyActiveContextEngineProjection = async'

    if ((Count-Literal $CandidateText $PromptHydrationStartNeedle) -ne 1) {
        throw "V3 prompt-hydration start anchor is not exactly one."
    }
    if ((Count-Literal $CandidateText $ApplyActiveNeedle) -ne 1) {
        throw "applyActiveContextEngineProjection boundary is not exactly one."
    }

    $PromptStart = $CandidateText.IndexOf(
        $PromptHydrationStartNeedle,
        [System.StringComparison]::Ordinal
    )
    $ApplyActiveStart = $CandidateText.IndexOf(
        $ApplyActiveNeedle,
        $PromptStart + $PromptHydrationStartNeedle.Length,
        [System.StringComparison]::Ordinal
    )
    if ($PromptStart -lt 0 -or $ApplyActiveStart -le $PromptStart) {
        throw "Could not isolate V3 prompt-hydration block."
    }

    $RestoredFreshProjection = @'
const applyFreshThreadContinuityProjection = () => {
		const projection = projectContextEngineAssemblyForCodex({
			assembledMessages: historyMessages,
			originalHistoryMessages: historyMessages,
			prompt: params.prompt,
			maxRenderedContextChars: codexContextProjectionMaxChars
		});
		promptText = projection.promptText;
		promptContextRange = projection.promptContextRange;
		prePromptMessageCount = projection.prePromptMessageCount;
	};
'@

    $CandidateText =
        $CandidateText.Substring(0, $PromptStart) +
        $RestoredFreshProjection +
        $CandidateText.Substring($ApplyActiveStart)

    # ------------------------------------------------------------------
    # 2. Restore the original no-context continuity projection function.
    #    The native bootstrap will no longer depend on this path.
    # ------------------------------------------------------------------
    $ContinuityStartNeedle =
        'const applyNoContextEngineContinuityProjection = async (action, binding) => {'
    $ContinuityEndNeedle =
        'const forgeLunaSidecarsForContinuityV2 = globalThis.__forgeCodexLunaSidecarsV2; // FORGE_CODEX_DUAL_WARM_THREADS_V2_1'

    if ((Count-Literal $CandidateText $ContinuityStartNeedle) -ne 1) {
        throw "V3 async continuity function anchor is not exactly one."
    }
    if ((Count-Literal $CandidateText $ContinuityEndNeedle) -ne 1) {
        throw "Dual-warm continuity boundary is not exactly one."
    }

    $ContinuityStart = $CandidateText.IndexOf(
        $ContinuityStartNeedle,
        [System.StringComparison]::Ordinal
    )
    $ContinuityEnd = $CandidateText.IndexOf(
        $ContinuityEndNeedle,
        $ContinuityStart + $ContinuityStartNeedle.Length,
        [System.StringComparison]::Ordinal
    )
    if ($ContinuityStart -lt 0 -or $ContinuityEnd -le $ContinuityStart) {
        throw "Could not isolate V3 continuity function."
    }

    $RestoredContinuity = @'
const applyNoContextEngineContinuityProjection = (action, binding) => {
		if (activeContextEngine || !historyMessages.some((message) => message.role === "user")) return false;
		if (action === "resumed" && precomputedStaleBindingContinuityProjectionApplied) return true;
		if (action === "started" && staleBindingContinuityForcedFreshStart) return true;
		if (action === "started" && inactiveThreadBootstrapBindingForcedFreshStart) return false;
		if (action === "resumed" && binding) return applyResumeStaleBindingContinuityProjection(binding);
		if (action === "started") {
			applyFreshThreadContinuityProjection();
			return true;
		}
		return false;
	};
'@

    $CandidateText =
        $CandidateText.Substring(0, $ContinuityStart) +
        $RestoredContinuity +
        $CandidateText.Substring($ContinuityEnd)

    $AsyncCallNeedle =
        'if (!forgeMonitorWarmProjectionV104 && await applyNoContextEngineContinuityProjection(thread.lifecycle.action, thread)) await rebuildCodexTurnPromptTextFromCurrentProjection();'
    $SyncCall =
        'if (!forgeMonitorWarmProjectionV104 && applyNoContextEngineContinuityProjection(thread.lifecycle.action, thread)) await rebuildCodexTurnPromptTextFromCurrentProjection();'

    if ((Count-Literal $CandidateText $AsyncCallNeedle) -ne 1) {
        throw "V3 async continuity call site is not exactly one."
    }
    $CandidateText = $CandidateText.Replace($AsyncCallNeedle, $SyncCall)

    # ------------------------------------------------------------------
    # 3. Add run-scoped helpers/state for a one-time native Luna bootstrap.
    # ------------------------------------------------------------------
    $RunStateNeedle = 'let latestStartupErrorNotification;'
    if ((Count-Literal $CandidateText $RunStateNeedle) -ne 1) {
        throw "Run-scoped state anchor is not exactly one."
    }

    $NativeHelpers = @'
// FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_30K_V5
const FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5 = 30_000 * 4;
let forgeFreshLunaNativeCanonBootstrappedV5 = false;
let forgeFreshLunaNativeCanonPairKeysV5;

const forgeFreshLunaCanonicalMessageTextV5 = (message) => {
	if (!message || typeof message !== "object") return "";
	const content = message.content;
	if (typeof content === "string") return content.trim();
	if (!Array.isArray(content)) return "";
	return content.flatMap((part) => {
		if (!part || typeof part !== "object") return [];
		const type = typeof part.type === "string" ? part.type : "";
		if (
			(type === "text" || type === "input_text" || type === "output_text") &&
			typeof part.text === "string"
		) return [part.text];
		return [];
	}).join("\n").trim();
};

const forgeFreshLunaCanonicalUserTextV5 = (message, rawText) => {
	const source =
		typeof message?.sourceChannel === "string" && message.sourceChannel.trim()
			? message.sourceChannel.trim()
			: void 0;
	const senderLabel =
		typeof message?.senderLabel === "string" && message.senderLabel.trim()
			? message.senderLabel.trim()
			: typeof message?.senderName === "string" && message.senderName.trim()
				? `${message.senderName.trim()}${
					typeof message?.senderId === "string" && message.senderId.trim()
						? ` (${message.senderId.trim()})`
						: ""
				}`
				: typeof message?.senderId === "string" && message.senderId.trim()
					? message.senderId.trim()
					: void 0;
	let timestamp;
	if (typeof message?.timestamp === "number" && Number.isFinite(message.timestamp)) {
		timestamp = new Date(message.timestamp).toISOString();
	} else if (typeof message?.timestamp === "string" && message.timestamp.trim()) {
		const parsed = Date.parse(message.timestamp);
		if (Number.isFinite(parsed)) timestamp = new Date(parsed).toISOString();
	}
	const metadata = [
		source ? source[0].toUpperCase() + source.slice(1) : "Canonical",
		senderLabel ? `user ${senderLabel}` : void 0,
		timestamp
	].filter(Boolean).join(" | ");
	return `[${metadata}]\n${rawText}`;
};

const forgeFreshLunaCanonicalPairKeyV5 = (userText, assistantText) =>
	JSON.stringify([userText, assistantText]);

const forgeFreshLunaNativeCanonSelectionV5 = (messages) => {
	const records = [];
	for (const message of messages ?? []) {
		if (!message || (message.role !== "user" && message.role !== "assistant")) continue;
		const rawText = forgeFreshLunaCanonicalMessageTextV5(message);
		if (!rawText) continue;
		const text =
			message.role === "user"
				? forgeFreshLunaCanonicalUserTextV5(message, rawText)
				: rawText;
		records.push({
			role: message.role,
			rawText,
			text
		});
	}

	const selected = [];
	let renderedChars = 0;
	for (let index = records.length - 1; index >= 0; index -= 1) {
		const record = records[index];
		const nextChars = record.text.length;
		if (selected.length > 0 && renderedChars + nextChars > FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5) {
			break;
		}
		if (selected.length === 0 && nextChars > FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5) {
			selected.unshift({
				...record,
				text: truncateUtf16Safe(record.text, FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5)
			});
			renderedChars = selected[0].text.length;
			break;
		}
		selected.unshift(record);
		renderedChars += nextChars;
	}

	while (selected.length > 0 && selected[0].role === "assistant") selected.shift();

	const pairKeys = new Set();
	let pendingUserText;
	for (const record of selected) {
		if (record.role === "user") {
			pendingUserText = record.rawText;
			continue;
		}
		if (record.role === "assistant" && pendingUserText !== void 0) {
			pairKeys.add(forgeFreshLunaCanonicalPairKeyV5(pendingUserText, record.rawText));
			pendingUserText = void 0;
		}
	}

	const items = selected.map((record) => ({
		type: "message",
		role: record.role,
		content: [{
			type: record.role === "user" ? "input_text" : "output_text",
			text: record.text
		}]
	}));

	return {
		items,
		pairKeys,
		renderedChars,
		messageCount: selected.length
	};
};

'@

    $CandidateText = $CandidateText.Replace(
        $RunStateNeedle,
        $NativeHelpers + $RunStateNeedle
    )

    # ------------------------------------------------------------------
    # 4. Inject the canonical native tail immediately before the existing
    #    bidirectional native-delta bridge / turn-start path.
    # ------------------------------------------------------------------
    $PreDeltaNeedle = 'rateLimitsRevisionBeforeLastTurnStart = readCodexRateLimitsRevision(client);'

    if ((Count-Literal $CandidateText $PreDeltaNeedle) -ne 1) {
        throw "Pre-native-delta single-line anchor is not exactly one."
    }

    $JsNL = if ($CandidateText.Contains("`r`n")) { "`r`n" } else { "`n" }

    $NativeBootstrap = @'

		if (
			!forgeFreshLunaNativeCanonBootstrappedV5 &&
			thread.lifecycle.action === "started" &&
			(params.modelId ?? "").trim().toLowerCase().split("/").at(-1) === "gpt-5.6-luna"
		) {
			const forgeFreshLunaCanonicalMessagesV5 = await readMirroredSessionHistoryMessages({
				forgeCanonicalSessionFile: true,
				agentId: sessionAgentId,
				sessionFile: params.sessionFile,
				sessionId: params.sessionId,
				sessionKey: contextSessionKey
			});
			const forgeFreshLunaNativeSelectionV5 =
				forgeFreshLunaNativeCanonSelectionV5(forgeFreshLunaCanonicalMessagesV5 ?? []);

			if (forgeFreshLunaNativeSelectionV5.items.length > 0) {
				await client.request("thread/inject_items", {
					threadId: thread.threadId,
					items: forgeFreshLunaNativeSelectionV5.items
				}, {
					timeoutMs: params.timeoutMs,
					signal: runAbortController.signal
				});
				forgeFreshLunaNativeCanonBootstrappedV5 = true;
				forgeFreshLunaNativeCanonPairKeysV5 = forgeFreshLunaNativeSelectionV5.pairKeys;
				embeddedAgentLog.info("forge fresh Luna canonical native bootstrap injected", {
					runId: params.runId,
					sessionId: params.sessionId,
					sessionFile: params.sessionFile,
					threadId: thread.threadId,
					messageCount: forgeFreshLunaNativeSelectionV5.messageCount,
					renderedChars: forgeFreshLunaNativeSelectionV5.renderedChars,
					maxRenderedChars: FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5
				});
			} else {
				embeddedAgentLog.warn("forge fresh Luna canonical native bootstrap had no messages", {
					runId: params.runId,
					sessionId: params.sessionId,
					sessionFile: params.sessionFile,
					threadId: thread.threadId
				});
			}
		}


'@

    # Match the candidate bundle's own newline style before insertion.
    $NativeBootstrap = $NativeBootstrap -replace "`r`n|`r|`n", $JsNL
    $PreDeltaIndex = $CandidateText.IndexOf(
        $PreDeltaNeedle,
        [System.StringComparison]::Ordinal
    )
    if ($PreDeltaIndex -lt 0) {
        throw "Pre-native-delta single-line anchor disappeared during candidate build."
    }
    $CandidateText = $CandidateText.Insert(
        $PreDeltaIndex + $PreDeltaNeedle.Length,
        $NativeBootstrap
    )

    # ------------------------------------------------------------------
    # 5. Exact-pair dedupe: if an existing pending delta pair is already in
    #    the native canonical bootstrap, mark its ID delivered on this thread.
    #    The existing bridge then keeps its normal ACK/confirmation semantics.
    # ------------------------------------------------------------------
    $FreshDeltaNeedle =
        'const forgeNativeDeltaFreshV1 = forgeNativeDeltaRawV1.exchanges.filter((forgeNativeDeltaExchangeV1) => !forgeNativeDeltaDeliveredV1.has(forgeNativeDeltaExchangeV1.id));'

    if ((Count-Literal $CandidateText $FreshDeltaNeedle) -ne 1) {
        throw "Native-delta fresh-filter anchor is not exactly one."
    }

    $DedupedFreshDelta = @'
if (
		            forgeNativeDeltaTargetSideV2 === "luna" &&
		            forgeFreshLunaNativeCanonPairKeysV5 instanceof Set &&
		            forgeFreshLunaNativeCanonPairKeysV5.size > 0
		        ) {
		            const forgeFreshLunaCanonCoveredAtV5 = Date.now();
		            for (const forgeNativeDeltaExchangeV1 of forgeNativeDeltaRawV1.exchanges) {
		                if (
		                    forgeFreshLunaNativeCanonPairKeysV5.has(
		                        forgeFreshLunaCanonicalPairKeyV5(
		                            forgeNativeDeltaExchangeV1.userText,
		                            forgeNativeDeltaExchangeV1.assistantText
		                        )
		                    )
		                ) {
		                    forgeNativeDeltaDeliveredV1.set(
		                        forgeNativeDeltaExchangeV1.id,
		                        forgeFreshLunaCanonCoveredAtV5
		                    );
		                }
		            }
		        }
		        const forgeNativeDeltaFreshV1 = forgeNativeDeltaRawV1.exchanges.filter((forgeNativeDeltaExchangeV1) => !forgeNativeDeltaDeliveredV1.has(forgeNativeDeltaExchangeV1.id));
'@

    $CandidateText = $CandidateText.Replace($FreshDeltaNeedle, $DedupedFreshDelta)

    # ------------------------------------------------------------------
    # Candidate invariants.
    # ------------------------------------------------------------------
    if ($CandidateText.Contains($V3Marker)) {
        throw "Dead V3 prompt-hydration marker survived candidate rebuild."
    }
    if ($CandidateText.Contains($V4RunMarker)) {
        throw "Dead V4 prompt read-flag marker survived candidate rebuild."
    }
    if ((Count-Literal $CandidateText $V5Marker) -ne 1) {
        throw "V5 native-bootstrap marker count is not exactly one."
    }
    if ((Count-Literal $CandidateText 'FORGE_LUNA_NATIVE_CANON_BOOTSTRAP_MAX_CHARS_V5 = 30_000 * 4') -ne 1) {
        throw "V5 30k native bootstrap cap is not exactly one."
    }
    if ((Count-Literal $CandidateText 'thread.lifecycle.action === "started"') -lt 1) {
        throw "Fresh-thread lifecycle gate missing from V5 candidate."
    }
    if ((Count-Literal $CandidateText 'forgeCanonicalSessionFile: true') -ne 1) {
        throw "Canonical file resolver bypass is not scoped to exactly one native bootstrap read."
    }
    if ((Count-Literal $CandidateText 'forgeFreshLunaCanonicalPairKeyV5') -lt 2) {
        throw "Canonical/native-delta exact-pair dedupe is not fully wired."
    }
    if ((Count-Literal $CandidateText 'await applyNoContextEngineContinuityProjection') -ne 0) {
        throw "Dead async prompt-hydration call remains in candidate."
    }
    if ((Count-Literal $CandidateText 'const applyNoContextEngineContinuityProjection = (action, binding) => {') -ne 1) {
        throw "Baseline synchronous continuity function was not restored exactly once."
    }
    if ((Count-Literal $CandidateText 'if (!forgeMonitorWarmProjectionV104 && applyNoContextEngineContinuityProjection(thread.lifecycle.action, thread))') -ne 1) {
        throw "Existing monitor projection bypass was not preserved."
    }

    # There should now be three native inject sites:
    # 1 fresh canon bootstrap
    # 2 cross-model native delta
    # 3 transient-tool clean pair re-injection
    if ((Count-Literal $CandidateText 'thread/inject_items') -ne 3) {
        throw "Expected exactly three thread/inject_items sites after V5 candidate build."
    }

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $StageDir = "$env:USERPROFILE\Desktop\forge-luna-native-canon-v5-1-$Stamp"
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

    $RunBackup = Join-Path $StageDir "run-attempt.pre-v5-backup.js"
    $ProviderReference = Join-Path $StageDir "provider-capabilities.v4-reference.js"
    $RunCandidate = Join-Path $StageDir "run-attempt.v5-native-canon-candidate.js"
    $RollbackPath = Join-Path $StageDir "ROLLBACK-LUNA-NATIVE-CANON-V5-1.ps1"

    [IO.File]::Copy($RunAttempt, $RunBackup, $true)
    [IO.File]::Copy($Provider, $ProviderReference, $true)

    if ((Sha256 $RunBackup) -ne $ExpectedRunHash) {
        throw "V5 run backup SHA mismatch."
    }
    if ((Sha256 $ProviderReference) -ne $ExpectedProviderHash) {
        throw "V4 provider reference SHA mismatch."
    }

    [IO.File]::WriteAllText(
        $RunCandidate,
        $CandidateText,
        [Text.UTF8Encoding]::new($false)
    )

    & node --check $RunCandidate
    if ($LASTEXITCODE -ne 0) {
        throw "V5 run-attempt candidate failed node --check."
    }

    $CandidateHash = Sha256 $RunCandidate

    $RollbackText = @"
`$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

`$RunAttempt = "$RunAttempt"
`$Provider = "$Provider"
`$RunBackup = "$RunBackup"
`$ExpectedRunHash = "$ExpectedRunHash"
`$ExpectedProviderHash = "$ExpectedProviderHash"

function Sha256([string]`$Path) {
    return (Get-FileHash -LiteralPath `$Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ((Sha256 `$RunBackup) -ne `$ExpectedRunHash) {
    throw "Rollback run backup SHA mismatch."
}
if ((Sha256 `$Provider) -ne `$ExpectedProviderHash) {
    throw "Provider changed since V5 apply; refusing partial rollback."
}

[IO.File]::Copy(`$RunBackup, `$RunAttempt, `$true)

& node --check `$RunAttempt
if (`$LASTEXITCODE -ne 0) {
    throw "Restored pre-V5 run-attempt failed node --check."
}
if ((Sha256 `$RunAttempt) -ne `$ExpectedRunHash) {
    throw "Restored pre-V5 run-attempt SHA mismatch."
}

openclaw gateway restart
if (`$LASTEXITCODE -ne 0) {
    throw "Gateway restart failed during V5 rollback."
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
    throw "Pre-V5 bytes restored, but gateway RPC did not become healthy within 120 seconds."
}

Write-Host ""
Write-Host "PASS - rolled V5 back to exact pre-V5 V4 run bundle." -ForegroundColor Green
Write-Host "Run SHA:      `$(Sha256 `$RunAttempt)"
Write-Host "Provider SHA: `$(Sha256 `$Provider)"
"@

    [IO.File]::WriteAllText(
        $RollbackPath,
        $RollbackText,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host ""
    Write-Host "=== LUNA NATIVE CANON BOOTSTRAP V5.1 PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host "Run live SHA:       $RunHash"
    Write-Host "Provider live SHA:  $ProviderHash"
    Write-Host "Candidate SHA:      $CandidateHash"
    Write-Host "Stage:              $StageDir"
    Write-Host "Backup:             $RunBackup"
    Write-Host "Rollback:           powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
    Write-Host "Syntax:             PASS"
    Write-Host ""
    Write-Host "V5 architecture:"
    Write-Host "  - dead V3/V4 prompt hydration removed from run-attempt"
    Write-Host "  - provider V4 canonical-file sanitizer/bypass retained"
    Write-Host "  - fresh Luna only: native canon injected before turn/start"
    Write-Host "  - max native canon text = 120,000 chars (~30k tokens)"
    Write-Host "  - warm Luna unchanged"
    Write-Host "  - Sol unchanged"
    Write-Host "  - existing native delta remains active"
    Write-Host "  - exact already-covered delta pairs are de-duplicated"
    Write-Host "  - monitor projection bypass remains unchanged"
    Write-Host ""

    if ($PreflightOnly) {
        Write-Host "PASS - PREFLIGHT ONLY. Live files and gateway unchanged." -ForegroundColor Green
        return
    }

    $MutationStarted = $false
    try {
        if ((Sha256 $RunAttempt) -ne $ExpectedRunHash) {
            throw "run-attempt changed after preflight. Nothing modified."
        }
        if ((Sha256 $Provider) -ne $ExpectedProviderHash) {
            throw "provider changed after preflight. Nothing modified."
        }

        $MutationStarted = $true
        [IO.File]::Copy($RunCandidate, $RunAttempt, $true)

        & node --check $RunAttempt
        if ($LASTEXITCODE -ne 0) {
            throw "Live V5 run-attempt failed node --check."
        }

        $Verify = [IO.File]::ReadAllText($RunAttempt)
        if ((Count-Literal $Verify $V5Marker) -ne 1) {
            throw "Live V5 marker verification failed."
        }
        if ($Verify.Contains($V3Marker) -or $Verify.Contains($V4RunMarker)) {
            throw "Dead prompt-hydration markers remain live after V5 apply."
        }
        if ((Sha256 $Provider) -ne $ExpectedProviderHash) {
            throw "Provider changed during V5 apply."
        }

        openclaw gateway restart
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway restart failed after V5 apply."
        }

        if (-not (Wait-GatewayHealthy -TimeoutSeconds 120 -DelaySeconds 5)) {
            throw "Gateway did not become RPC-healthy within 120 seconds after V5 apply."
        }
    }
    catch {
        if ($MutationStarted) {
            Write-Host ""
            Write-Host "V5 APPLY FAILED - restoring exact pre-V5 run bundle." -ForegroundColor Red
            [IO.File]::Copy($RunBackup, $RunAttempt, $true)

            if ((Sha256 $RunAttempt) -ne $ExpectedRunHash) {
                throw "Automatic V5 rollback failed to restore run-attempt SHA."
            }

            try {
                openclaw gateway restart | Out-Host
                [void](Wait-GatewayHealthy -TimeoutSeconds 120 -DelaySeconds 5)
            } catch {}
        }
        throw
    }

    Write-Host ""
    Write-Host "PASS - LUNA NATIVE CANON BOOTSTRAP V5.1 IS LIVE." -ForegroundColor Green
    Write-Host "Run SHA:      $(Sha256 $RunAttempt)"
    Write-Host "Provider SHA: $(Sha256 $Provider)"
    Write-Host "Stage:        $StageDir"
    Write-Host ""
    Write-Host "ROLLBACK COMMAND:" -ForegroundColor Yellow
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$RollbackPath`""
    Write-Host ""
    Write-Host "Acceptance proof:"
    Write-Host "  1. Trigger one ordinary ambient Luna turn."
    Write-Host "  2. New rollout should contain substantially more than 40 historical messages."
    Write-Host "  3. First input should rise materially above the old ~14.3k baseline."
    Write-Host "  4. Second Luna turn should resume the same thread and show normal cache reuse."
}