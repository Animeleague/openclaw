param(
    [ValidateSet("apply","status","rollback")]
    [string]$Action = "apply"
)

$ErrorActionPreference = "Stop"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$RunFile = Join-Path $Dist "run-attempt-FUyOjGCV.js"

$PatchId = "FORGE_CODEX_TURN_PAYLOAD_DIAG_V1"
$RequiredV2 = "FORGE_CODEX_STABLE_TOOL_CATALOG_V2"
$StateDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-turn-payload-diag-v1"
$Manifest = Join-Path $StateDir "manifest.json"
$BackupRun = Join-Path $StateDir "run-attempt.pre-diag.js"
$DiagLog = Join-Path $env:USERPROFILE ".openclaw\logs\forge-codex-turn-payload-diag.jsonl"

function Assert-Exists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file not found: $Path"
    }
}

function Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Replace-Once([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "Preflight failed: '$Label' occurred $Count times; expected 1. Nothing was modified."
    }
    $Text.Replace($Old, $New)
}

function Node-Check([string]$Path) {
    & node --check $Path
    if ($LASTEXITCODE -ne 0) { throw "node --check failed: $Path" }
}

function Show-Status {
    Assert-Exists $RunFile
    $R = [System.IO.File]::ReadAllText($RunFile)

    Write-Host ""
    Write-Host "=== Forge Codex turn payload diagnostics V1 ==="
    Write-Host "Diagnostic installed: $($R.Contains($PatchId))"
    Write-Host "Stable catalogue V2:  $($R.Contains($RequiredV2))"
    Write-Host "run-attempt SHA256:    $(Sha $RunFile)"
    Write-Host "Diagnostic log exists: $(Test-Path -LiteralPath $DiagLog)"
    Write-Host "Diagnostic log:        $DiagLog"
    if (Test-Path -LiteralPath $Manifest) {
        Write-Host "Rollback state:         $StateDir"
    }
    Write-Host ""
}

Assert-Exists $RunFile

if ($Action -eq "status") {
    Show-Status
    exit 0
}

if ($Action -eq "rollback") {
    Assert-Exists $Manifest
    Assert-Exists $BackupRun

    $M = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ([string]$M.patchId -ne $PatchId) { throw "Rollback manifest mismatch." }

    if ([string]$M.patchedRunSha256 -and (Sha $RunFile) -ne [string]$M.patchedRunSha256) {
        throw "run-attempt changed after diagnostics were applied; refusing to overwrite newer edits."
    }

    Copy-Item -LiteralPath $BackupRun -Destination $RunFile -Force
    Node-Check $RunFile

    if ((Sha $RunFile) -ne [string]$M.originalRunSha256) {
        throw "Diagnostic rollback SHA mismatch."
    }

    Write-Host ""
    Write-Host "DIAG V1 ROLLBACK PASS"
    Write-Host "Stable catalogue V2 is preserved because rollback restores the post-V2 file."
    Write-Host "Restart once: openclaw gateway restart"
    exit 0
}

# ---------------- APPLY ----------------

$Run = [System.IO.File]::ReadAllText($RunFile)

if ($Run.Contains($PatchId)) {
    Write-Host "Diagnostics already appear installed; no changes made."
    Show-Status
    exit 0
}

if (-not $Run.Contains($RequiredV2)) {
    throw "Stable catalogue V2 marker is not present. Refusing to install diagnostics on an unexpected baseline."
}

if (-not $Run.TrimStart().StartsWith("import ")) {
    throw "Unexpected run-attempt file header; expected an ESM import. Nothing was modified."
}

$HelperAnchor = "function buildCodexSystemPromptReport(params) {"
$RequestBytesAnchor = "`t`t codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));"
# The bundled file uses one tab before the statement; tolerate that exact known form below if the two-tab form is absent.
if (-not $Run.Contains($RequestBytesAnchor)) {
    $RequestBytesAnchor = "`t`t codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));".Replace("`t`t ", "`t`t")
}
if (-not $Run.Contains($RequestBytesAnchor)) {
    $RequestBytesAnchor = "`t`t codexModelCallDiagnostics.setRequestPayloadBytes(utf8JsonByteLength(turnStartParams));".Replace("`t`t", "`t")
}

$HelperCount = ([regex]::Matches($Run, [regex]::Escape($HelperAnchor))).Count
$RequestCount = ([regex]::Matches($Run, [regex]::Escape($RequestBytesAnchor))).Count
if ($HelperCount -ne 1) { throw "Preflight failed: helper anchor occurred $HelperCount times; expected 1. Nothing was modified." }
if ($RequestCount -ne 1) { throw "Preflight failed: turn-start anchor occurred $RequestCount times; expected 1. Nothing was modified." }

$ImportLine = 'import { appendFileSync as forgeCodexTurnDiagAppendFileSync } from "node:fs"; // FORGE_CODEX_TURN_PAYLOAD_DIAG_V1'

$Helper = @'
// FORGE_CODEX_TURN_PAYLOAD_DIAG_V1
const FORGE_CODEX_TURN_PAYLOAD_DIAG_PATH_V1 = `${process.env.USERPROFILE ?? "."}/.openclaw/logs/forge-codex-turn-payload-diag.jsonl`;

function forgeCodexTurnDiagSerializeV1(value) {
	try {
		const serialized = JSON.stringify(value);
		return serialized === void 0 ? String(value) : serialized;
	} catch {
		return String(value);
	}
}

function forgeCodexTurnDiagHashV1(namespace, value) {
	return fingerprintCodexLogValue(`forge:codex:turn-payload:v1:${namespace}`, forgeCodexTurnDiagSerializeV1(value));
}

function forgeCodexTurnDiagTextV1(namespace, value) {
	const text = typeof value === "string" ? value : "";
	return {
		chars: text.length,
		bytes: Buffer.byteLength(text, "utf8"),
		fingerprint: forgeCodexTurnDiagHashV1(namespace, text)
	};
}

function forgeCodexTurnDiagInputV1(input) {
	if (!Array.isArray(input)) return {
		kind: typeof input,
		fingerprint: forgeCodexTurnDiagHashV1("input", input)
	};
	return {
		count: input.length,
		fingerprint: forgeCodexTurnDiagHashV1("input", input),
		items: input.map((item, index) => {
			const type = item && typeof item === "object" && typeof item.type === "string" ? item.type : typeof item;
			const result = {
				index,
				type,
				fingerprint: forgeCodexTurnDiagHashV1(`input:${index}`, item)
			};
			if (item && typeof item === "object" && typeof item.text === "string") {
				result.text = forgeCodexTurnDiagTextV1(`input:${index}:text`, item.text);
			}
			if (item && typeof item === "object" && typeof item.url === "string") {
				result.url = {
					chars: item.url.length,
					fingerprint: forgeCodexTurnDiagHashV1(`input:${index}:url`, item.url)
				};
			}
			return result;
		})
	};
}

function forgeCodexTurnDiagWithoutInputV1(turnStartParams) {
	if (!turnStartParams || typeof turnStartParams !== "object") return turnStartParams;
	const copy = { ...turnStartParams };
	delete copy.input;
	return copy;
}

function forgeWriteCodexTurnPayloadDiagV1(params, details) {
	try {
		const turnStartParams = details.turnStartParams ?? {};
		const collaborationMode = turnStartParams.collaborationMode ?? null;
		const collaborationSettings = collaborationMode?.settings ?? null;
		const workspace = details.workspaceBootstrapContext ?? {};
		const record = {
			kind: "turn-start-payload",
			ts: new Date().toISOString(),
			runId: params.runId ?? null,
			sessionId: params.sessionId ?? null,
			sessionKey: params.sessionKey ?? null,
			contextSessionKey: details.contextSessionKey ?? null,
			threadId: turnStartParams.threadId ?? details.threadId ?? null,
			provider: params.provider ?? null,
			requestedModel: params.modelId ?? null,
			model: turnStartParams.model ?? null,
			effort: turnStartParams.effort ?? null,
			serviceTier: turnStartParams.serviceTier ?? null,
			trigger: params.trigger ?? null,
			senderIsOwner: params.senderIsOwner ?? null,
			bootstrapContextMode: params.bootstrapContextMode ?? null,
			bootstrapContextRunKind: params.bootstrapContextRunKind ?? null,
			messageProvider: params.messageProvider ?? null,
			currentChannelId: params.currentChannelId ?? null,
			currentMessageId: params.currentMessageId ?? null,
			sourceReplyDeliveryMode: params.sourceReplyDeliveryMode ?? null,
			activeContextEngine: details.activeContextEngine === true,
			turnStartKeys: Object.keys(turnStartParams).toSorted(),
			turnStartFingerprint: forgeCodexTurnDiagHashV1("turn-start", turnStartParams),
			turnStartWithoutInputFingerprint: forgeCodexTurnDiagHashV1("turn-start-without-input", forgeCodexTurnDiagWithoutInputV1(turnStartParams)),
			cwdFingerprint: forgeCodexTurnDiagHashV1("cwd", turnStartParams.cwd ?? null),
			approvalPolicy: turnStartParams.approvalPolicy ?? null,
			approvalsReviewer: turnStartParams.approvalsReviewer ?? null,
			sandboxPolicyFingerprint: forgeCodexTurnDiagHashV1("sandbox-policy", turnStartParams.sandboxPolicy ?? null),
			environmentsFingerprint: forgeCodexTurnDiagHashV1("environments", turnStartParams.environments ?? null),
			input: forgeCodexTurnDiagInputV1(turnStartParams.input),
			promptText: forgeCodexTurnDiagTextV1("prompt-text", details.promptText),
			renderedDeveloperInstructions: forgeCodexTurnDiagTextV1("rendered-developer-instructions", details.renderedDeveloperInstructions),
			collaborationMode: collaborationMode ? {
				mode: collaborationMode.mode ?? null,
				fingerprint: forgeCodexTurnDiagHashV1("collaboration-mode", collaborationMode),
				model: collaborationSettings?.model ?? null,
				reasoningEffort: collaborationSettings?.reasoning_effort ?? null,
				developerInstructions: forgeCodexTurnDiagTextV1("collaboration-developer-instructions", collaborationSettings?.developer_instructions)
			} : null,
			workspaceBootstrap: {
				developerInstructions: forgeCodexTurnDiagTextV1("workspace-developer-instructions", workspace.developerInstructions),
				promptContext: forgeCodexTurnDiagTextV1("workspace-prompt-context", workspace.promptContext),
				turnScopedDeveloperInstructions: forgeCodexTurnDiagTextV1("workspace-turn-scoped-developer-instructions", workspace.turnScopedDeveloperInstructions),
				memoryCollaborationInstructions: forgeCodexTurnDiagTextV1("workspace-memory-collaboration-instructions", workspace.memoryCollaborationInstructions),
				heartbeatCollaborationInstructions: forgeCodexTurnDiagTextV1("workspace-heartbeat-collaboration-instructions", workspace.heartbeatCollaborationInstructions)
			},
			skillsCollaborationInstructions: forgeCodexTurnDiagTextV1("skills-collaboration-instructions", details.skillsCollaborationInstructions),
			historyMessages: {
				count: Array.isArray(details.historyMessages) ? details.historyMessages.length : null,
				fingerprint: forgeCodexTurnDiagHashV1("history-messages", details.historyMessages ?? null)
			},
			modelInputHistoryMessages: {
				count: Array.isArray(details.modelInputHistoryMessages) ? details.modelInputHistoryMessages.length : null,
				fingerprint: forgeCodexTurnDiagHashV1("model-input-history-messages", details.modelInputHistoryMessages ?? null)
			},
			prePromptMessageCount: details.prePromptMessageCount ?? null,
			promptContextRangeFingerprint: forgeCodexTurnDiagHashV1("prompt-context-range", details.promptContextRange ?? null),
			stableToolFingerprint: details.stableToolFingerprint ?? null,
			currentRegisteredToolFingerprint: details.currentRegisteredToolFingerprint ?? null,
			availableToolFingerprint: details.availableToolFingerprint ?? null
		};
		forgeCodexTurnDiagAppendFileSync(FORGE_CODEX_TURN_PAYLOAD_DIAG_PATH_V1, `${JSON.stringify(record)}\n`, { encoding: "utf8" });
	} catch {
		// Diagnostics must never affect Forge execution.
	}
}

'@

$Call = @'
		forgeWriteCodexTurnPayloadDiagV1(params, {
			turnStartParams,
			threadId: thread.threadId,
			contextSessionKey,
			promptText: codexTurnPromptText,
			renderedDeveloperInstructions: buildRenderedCodexDeveloperInstructions(),
			workspaceBootstrapContext,
			skillsCollaborationInstructions,
			historyMessages,
			modelInputHistoryMessages: codexModelInputHistoryMessages,
			prePromptMessageCount,
			promptContextRange,
			activeContextEngine: Boolean(activeContextEngine),
			stableToolFingerprint: codexDynamicToolsFingerprint(forgeStableToolCatalogV2),
			currentRegisteredToolFingerprint: codexDynamicToolsFingerprint(toolBridge.specs),
			availableToolFingerprint: codexDynamicToolsFingerprint(toolBridge.availableSpecs)
		});
'@

$Run2 = $ImportLine + "`n" + $Run
$Run2 = Replace-Once $Run2 $HelperAnchor ($Helper + $HelperAnchor) "helper insertion"
$Run2 = Replace-Once $Run2 $RequestBytesAnchor ($RequestBytesAnchor + "`n" + $Call.TrimEnd([char[]]"`r`n")) "turn-start diagnostic call"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
if ((Test-Path -LiteralPath $Manifest) -or (Test-Path -LiteralPath $BackupRun)) {
    throw "Diagnostic state directory already contains rollback files: $StateDir"
}

Copy-Item -LiteralPath $RunFile -Destination $BackupRun

$M = [ordered]@{
    patchId = $PatchId
    appliedAt = (Get-Date).ToString("o")
    runFile = $RunFile
    diagLog = $DiagLog
    originalRunSha256 = Sha $RunFile
    patchedRunSha256 = $null
}
$M | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding utf8

try {
    Write-NoBom $RunFile $Run2
    Node-Check $RunFile

    $PatchedText = [System.IO.File]::ReadAllText($RunFile)
    if (-not $PatchedText.Contains($PatchId)) { throw "Diagnostic marker missing after write." }
    if (-not $PatchedText.Contains($RequiredV2)) { throw "Stable catalogue V2 marker disappeared after write." }

    $M.patchedRunSha256 = Sha $RunFile
    $M | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding utf8
} catch {
    Copy-Item -LiteralPath $BackupRun -Destination $RunFile -Force
    throw
}

Write-Host ""
Write-Host "DIAG V1 APPLY PASS"
Write-Host ""
Write-Host "This patch is observation-only:"
Write-Host "  no prompt/cache fields changed"
Write-Host "  no tool permissions changed"
Write-Host "  no thread binding logic changed"
Write-Host "  large/sensitive values are hashed, not dumped"
Write-Host "  Stable Tool Catalogue V2 remains installed"
Write-Host ""
Write-Host "Restart once:"
Write-Host "  openclaw gateway restart"
Write-Host ""
Write-Host "Diagnostic log after turns:"
Write-Host "  $DiagLog"
