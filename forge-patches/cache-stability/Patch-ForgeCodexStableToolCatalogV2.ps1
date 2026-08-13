param(
    [ValidateSet("apply","status","rollback")]
    [string]$Action = "apply"
)

$ErrorActionPreference = "Stop"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$RunFile = Join-Path $Dist "run-attempt-FUyOjGCV.js"
$ThreadFile = Join-Path $Dist "thread-lifecycle-qWE88Dn2.js"

$PatchId = "FORGE_CODEX_STABLE_TOOL_CATALOG_V2"
$StateDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-stable-tool-catalog-v2"
$Manifest = Join-Path $StateDir "manifest.json"
$BackupRun = Join-Path $StateDir "run-attempt.original.js"
$BackupThread = Join-Path $StateDir "thread-lifecycle.original.js"

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
    Assert-Exists $ThreadFile
    $R = [System.IO.File]::ReadAllText($RunFile)
    $T = [System.IO.File]::ReadAllText($ThreadFile)

    Write-Host ""
    Write-Host "=== Forge Codex stable tool catalogue V2 ==="
    Write-Host "V2 run marker:        $($R.Contains($PatchId))"
    Write-Host "V2 lifecycle marker:  $($T.Contains($PatchId))"
    Write-Host "Old V1 run marker:    $($R.Contains('FORGE_STABLE_CODEX_TOOL_CATALOG_V1'))"
    Write-Host "Old V1 lifecycle:     $($T.Contains('FORGE_STABLE_CODEX_DEVELOPER_TOOL_MANIFEST_V1'))"
    Write-Host "Thread diag V1:       $($T.Contains('FORGE_CODEX_THREAD_DIAG_V1'))"
    Write-Host "Thread diag V2:       $($T.Contains('FORGE_CODEX_THREAD_DIAG_V2'))"
    Write-Host "run-attempt SHA256:   $(Sha $RunFile)"
    Write-Host "thread SHA256:        $(Sha $ThreadFile)"
    Write-Host ""

    $Core = Join-Path $env:APPDATA "npm\node_modules\openclaw\dist"
    $Legacy = @()
    if (Test-Path -LiteralPath $Core) {
        Get-ChildItem -LiteralPath $Core -File -Filter "openai-transport-stream-*.js" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $X = [System.IO.File]::ReadAllText($_.FullName)
                $Marks = @()
                if ($X.Contains("FORGE_GPT56_EXPLICIT_CACHE_BREAKPOINT_V1")) { $Marks += "wrong-route B1" }
                if ($X.Contains("FORGE_GPT56_CACHE_DIAG_V1")) { $Marks += "cache diag" }
                if ($X.Contains("FORGE_MODULE_LOAD")) { $Marks += "module probe" }
                if ($X.Contains("FORGE_PARAMS_ENTRY")) { $Marks += "params probe" }
                if ($Marks.Count) {
                    $Legacy += "$($Marks -join ', ') :: $($_.FullName)"
                }
            }
    }

    if ($Legacy.Count) {
        Write-Host "Legacy global OpenAI transport instrumentation still present (not used by Forge's Codex route):"
        $Legacy | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "Legacy global OpenAI transport instrumentation: none detected"
    }

    if (Test-Path -LiteralPath $Manifest) {
        Write-Host ""
        Write-Host "V2 rollback state: $StateDir"
    }
}

Assert-Exists $RunFile
Assert-Exists $ThreadFile

if ($Action -eq "status") {
    Show-Status
    exit 0
}

if ($Action -eq "rollback") {
    Assert-Exists $Manifest
    Assert-Exists $BackupRun
    Assert-Exists $BackupThread

    $M = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ([string]$M.patchId -ne $PatchId) { throw "Rollback manifest mismatch." }

    if ([string]$M.patchedRunSha256 -and (Sha $RunFile) -ne [string]$M.patchedRunSha256) {
        throw "run-attempt changed after V2 was applied; refusing to overwrite newer edits."
    }
    if ([string]$M.patchedThreadSha256 -and (Sha $ThreadFile) -ne [string]$M.patchedThreadSha256) {
        throw "thread-lifecycle changed after V2 was applied; refusing to overwrite newer edits."
    }

    Copy-Item -LiteralPath $BackupRun -Destination $RunFile -Force
    Copy-Item -LiteralPath $BackupThread -Destination $ThreadFile -Force

    Node-Check $RunFile
    Node-Check $ThreadFile

    if ((Sha $RunFile) -ne [string]$M.originalRunSha256) { throw "run-attempt rollback SHA mismatch." }
    if ((Sha $ThreadFile) -ne [string]$M.originalThreadSha256) { throw "thread-lifecycle rollback SHA mismatch." }

    Write-Host ""
    Write-Host "V2 ROLLBACK PASS"
    Write-Host "Restart the gateway once: openclaw gateway restart"
    exit 0
}

# ---------------- APPLY ----------------

$Run = [System.IO.File]::ReadAllText($RunFile)
$Thread = [System.IO.File]::ReadAllText($ThreadFile)

if ($Run.Contains($PatchId) -or $Thread.Contains($PatchId)) {
    Write-Host "V2 already appears installed; no changes made."
    Show-Status
    exit 0
}

if ($Run.Contains("FORGE_STABLE_CODEX_TOOL_CATALOG_V1") -or
    $Thread.Contains("FORGE_STABLE_CODEX_DEVELOPER_TOOL_MANIFEST_V1")) {
    throw "The abandoned V1 stable-tool patch is still present. Refusing to layer V2 over it."
}

$HelperAnchor = "function buildCodexSystemPromptReport(params) {"
$SelectionAnchor = "`tconst hadSessionFile = await pathExists(activeSessionFile);"
$Fp1 = "`t`t`tdynamicToolsFingerprint: codexDynamicToolsFingerprint(toolBridge.specs),"
$Fp2 = "`t`t`tlegacyDynamicToolsFingerprint: codexLegacyDynamicToolsFingerprint(toolBridge.specs)"
$ThreadTools = "`t`t`tdynamicTools: toolBridge.specs,"
$ManifestLine = "`tconst deferredToolNames = [...new Set(flattenCodexDynamicToolFunctions(dynamicTools).filter((tool) => tool.deferLoading === true).map((tool) => tool.name.trim()).filter(Boolean))].toSorted((left, right) => left.localeCompare(right));"

# Strict source-shape preflight before creating backups or writing anything.
foreach ($A in @(
    @{T=$Run; A=$HelperAnchor; L="helper insertion"},
    @{T=$Run; A=$SelectionAnchor; L="stable selection"},
    @{T=$Run; A=$Fp1; L="dynamic fingerprint"},
    @{T=$Run; A=$Fp2; L="legacy fingerprint"},
    @{T=$Run; A=$ThreadTools; L="thread dynamic tools"},
    @{T=$Thread; A=$ManifestLine; L="developer tool manifest"}
)) {
    $C = ([regex]::Matches($A.T, [regex]::Escape($A.A))).Count
    if ($C -ne 1) { throw "Preflight failed: '$($A.L)' occurred $C times; expected 1. Nothing was modified." }
}

$Helper = @'
// FORGE_CODEX_STABLE_TOOL_CATALOG_V2
const FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2 = /* @__PURE__ */ new Set([
	"cron",
	"gateway",
	"nodes"
]);
const forgeCodexStableToolCatalogV2 = /* @__PURE__ */ new Map();

function forgeCodexSpecMapV2(specs) {
	return new Map(flattenCodexDynamicToolFunctions(specs).map((tool) => [tool.name, tool]));
}

function forgeCloneDynamicToolSpecsV2(specs) {
	return JSON.parse(JSON.stringify(specs ?? []));
}

function forgeSelectStableToolCatalogV2(params, currentSpecs) {
	// Never share cached catalogue state across sessions.
	const sessionId = typeof params.sessionId === "string" ? params.sessionId.trim() : "";
	if (!sessionId) return currentSpecs;
	const key = `${sessionId}\0${params.provider ?? ""}\0${params.modelId ?? ""}`;
	const currentByName = forgeCodexSpecMapV2(currentSpecs);
	const hasFullOwnerTrio = [...FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2].every((name) => currentByName.has(name));

	// Seed/update ONLY from a genuine owner turn on which OpenClaw itself
	// naturally exposed all three owner-only tools. No fake owner identity.
	if (params.senderIsOwner === true && hasFullOwnerTrio) {
		const cloned = forgeCloneDynamicToolSpecsV2(currentSpecs);
		forgeCodexStableToolCatalogV2.set(key, cloned);
		if (forgeCodexStableToolCatalogV2.size > 128) {
			const oldest = forgeCodexStableToolCatalogV2.keys().next().value;
			if (oldest !== void 0) forgeCodexStableToolCatalogV2.delete(oldest);
		}
		return cloned;
	}

	// Unknown identity never gets catalogue substitution.
	if (params.senderIsOwner !== false) return currentSpecs;

	const cachedFull = forgeCodexStableToolCatalogV2.get(key);
	if (!cachedFull) return currentSpecs;
	const cachedByName = forgeCodexSpecMapV2(cachedFull);

	// Extremely narrow compatibility rule:
	// current non-owner catalogue must be IDENTICAL to cached owner catalogue
	// except that cron/gateway/nodes are absent. Anything else falls back to
	// OpenClaw's native behaviour and may rotate normally.
	for (const name of FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2) {
		if (currentByName.has(name) || !cachedByName.has(name)) return currentSpecs;
	}
	if (cachedByName.size !== currentByName.size + FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2.size) return currentSpecs;

	for (const [name, currentSpec] of currentByName) {
		const cachedSpec = cachedByName.get(name);
		if (!cachedSpec || JSON.stringify(cachedSpec) !== JSON.stringify(currentSpec)) return currentSpecs;
	}

	return cachedFull;
}

'@

$Run2 = Replace-Once $Run $HelperAnchor ($Helper + $HelperAnchor) "helper insertion"

$Selection = @'
	const forgeStableToolCatalogV2 = forgeSelectStableToolCatalogV2(params, toolBridge.specs);
	const hadSessionFile = await pathExists(activeSessionFile);
'@
$Run2 = Replace-Once $Run2 $SelectionAnchor $Selection.TrimEnd([char[]]"`r`n") "stable selection"
$Run2 = Replace-Once $Run2 $Fp1 "`t`t`tdynamicToolsFingerprint: codexDynamicToolsFingerprint(forgeStableToolCatalogV2)," "dynamic fingerprint"
$Run2 = Replace-Once $Run2 $Fp2 "`t`t`tlegacyDynamicToolsFingerprint: codexLegacyDynamicToolsFingerprint(forgeStableToolCatalogV2)" "legacy fingerprint"
$Run2 = Replace-Once $Run2 $ThreadTools "`t`t`tdynamicTools: forgeStableToolCatalogV2," "thread dynamic tools"

# Keep developer instructions stable across the proven owner-only trio flip
# without advertising those three deferred tools to non-owners. The base
# OpenClaw instruction already mentions cron/gateway/nodes generically.
$ManifestReplacement = "`tconst deferredToolNames = [...new Set(flattenCodexDynamicToolFunctions(dynamicTools).filter((tool) => tool.deferLoading === true).map((tool) => tool.name.trim()).filter(Boolean).filter((name) => !FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2.has(name)))].toSorted((left, right) => left.localeCompare(right)); // $PatchId"

# thread-lifecycle is a separate module, so give it its own local constant.
$ThreadConstAnchor = "function buildDeveloperInstructions(params, options = {}) {"
$ThreadConst = @'
// FORGE_CODEX_STABLE_TOOL_CATALOG_V2
const FORGE_CODEX_OWNER_ONLY_TOOL_NAMES_V2 = /* @__PURE__ */ new Set(["cron", "gateway", "nodes"]);
function buildDeveloperInstructions(params, options = {}) {
'@
$Thread2 = Replace-Once $Thread $ThreadConstAnchor $ThreadConst.TrimEnd([char[]]"`r`n") "lifecycle constant"
$Thread2 = Replace-Once $Thread2 $ManifestLine $ManifestReplacement "developer tool manifest"

# Back up the CURRENT known-good state (including our useful thread diagnostic).
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
if ((Test-Path -LiteralPath $Manifest) -or (Test-Path -LiteralPath $BackupRun) -or (Test-Path -LiteralPath $BackupThread)) {
    throw "V2 state directory already contains rollback files: $StateDir"
}

Copy-Item -LiteralPath $RunFile -Destination $BackupRun
Copy-Item -LiteralPath $ThreadFile -Destination $BackupThread

$M = [ordered]@{
    patchId = $PatchId
    appliedAt = (Get-Date).ToString("o")
    runFile = $RunFile
    threadFile = $ThreadFile
    originalRunSha256 = Sha $RunFile
    originalThreadSha256 = Sha $ThreadFile
    patchedRunSha256 = $null
    patchedThreadSha256 = $null
}
$M | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding utf8

try {
    Write-NoBom $RunFile $Run2
    Write-NoBom $ThreadFile $Thread2

    Node-Check $RunFile
    Node-Check $ThreadFile

    $M.patchedRunSha256 = Sha $RunFile
    $M.patchedThreadSha256 = Sha $ThreadFile
    $M | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding utf8
}
catch {
    Copy-Item -LiteralPath $BackupRun -Destination $RunFile -Force
    Copy-Item -LiteralPath $BackupThread -Destination $ThreadFile -Force
    throw
}

Write-Host ""
Write-Host "V2 APPLY PASS"
Write-Host "Rollback state: $StateDir"
Write-Host ""
Write-Host "Security invariants:"
Write-Host "  senderIsOwner untouched"
Write-Host "  current-turn toolMap untouched"
Write-Host "  no privileged executor cached"
Write-Host "  only inert Codex specs are reused"
Write-Host "  any catalogue difference beyond cron/gateway/nodes falls back to native rotation"
Write-Host ""
Write-Host "Restart once:"
Write-Host "  openclaw gateway restart"
