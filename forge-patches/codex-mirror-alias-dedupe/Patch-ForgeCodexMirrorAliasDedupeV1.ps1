param(
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$PatchId = "FORGE_CODEX_MIRROR_ALIAS_DEDUPE_V1"
$ExpectedOpenClawVersion = "2026.7.1"

$Dist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$Target = Join-Path $Dist "provider-capabilities-CDnHbmUZ.js"
$Package = Join-Path (Split-Path $Dist -Parent) "package.json"

$StateDir = Join-Path $env:USERPROFILE ".openclaw\.forge-patches\codex-mirror-alias-dedupe-v1"
$Backup = Join-Path $StateDir "provider-capabilities.pre-v1.js"
$Manifest = Join-Path $StateDir "manifest.json"

$MirrorFunctionAnchor = 'async function mirrorCodexAppServerTranscript(params) {'

$AppendOld = @'
			const appended = await transcript.appendMessage({
				message: messageToAppend,
				idempotencyLookup: idempotencyKey ? "caller-checked" : "scan",
				cwd: params.cwd
			});
'@

$AppendNew = @'
			const forgeMessageToAppendV1 = compactCodexMirroredToolAliasesV1(messageToAppend);
			const appended = await transcript.appendMessage({
				message: forgeMessageToAppendV1,
				idempotencyLookup: idempotencyKey ? "caller-checked" : "scan",
				cwd: params.cwd
			});
'@

$Helper = @'
function compactCodexMirroredToolAliasesV1(message) {
	// FORGE_CODEX_MIRROR_ALIAS_DEDUPE_V1
	// Compact only byte-equivalent compatibility aliases on the copy written
	// to the OpenClaw transcript. Live Codex protocol/tool execution is untouched.
	if (!message || typeof message !== "object") return message;
	if (!Array.isArray(message.content)) return message;
	let changed = false;
	const content = message.content.map((block) => {
		if (!block || typeof block !== "object" || Array.isArray(block)) return block;
		if (message.role === "assistant" && block.type === "toolCall" && Object.prototype.hasOwnProperty.call(block, "arguments") && Object.prototype.hasOwnProperty.call(block, "input")) {
			let equal = false;
			try {
				equal = JSON.stringify(block.arguments) === JSON.stringify(block.input);
			} catch {}
			if (!equal) return block;
			const next = { ...block };
			delete next.input;
			changed = true;
			return next;
		}
		if (message.role === "toolResult" && block.type === "toolResult" && typeof block.text === "string" && typeof block.content === "string" && block.text === block.content) {
			const next = { ...block };
			delete next.content;
			changed = true;
			return next;
		}
		return block;
	});
	return changed ? {
		...message,
		content
	} : message;
}
'@

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Count-Literal([string]$Text, [string]$Needle) {
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function Assert-NodeSyntax([string]$Path) {
    & node --check $Path | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "node --check failed: $Path"
    }
}

if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
    throw "Target not found: $Target"
}

if (-not (Test-Path -LiteralPath $Package -PathType Leaf)) {
    throw "Codex package.json not found: $Package"
}

$OpenClawVersion = (& openclaw --version 2>$null | Out-String).Trim()
if ($OpenClawVersion -notmatch [regex]::Escape($ExpectedOpenClawVersion)) {
    throw "This patch is pinned to OpenClaw $ExpectedOpenClawVersion. Found: $OpenClawVersion. Nothing changed."
}
$CodexPackageVersion = if (Test-Path -LiteralPath $Package -PathType Leaf) {
    [string]((Get-Content -LiteralPath $Package -Raw | ConvertFrom-Json).version)
} else {
    "(unknown)"
}

$Text = [System.IO.File]::ReadAllText($Target)
$Hash = Get-Sha256 $Target

$MarkerCount = Count-Literal $Text $PatchId
$MirrorCount = Count-Literal $Text $MirrorFunctionAnchor
$AppendOldCount = Count-Literal $Text $AppendOld
$AppendNewCount = Count-Literal $Text $AppendNew

function Show-Status {
    Write-Host ""
    Write-Host "Forge Codex Mirror Alias Dedupe V1"
    Write-Host "================================="
    Write-Host "OpenClaw version:   $OpenClawVersion"
    Write-Host "Codex pkg version:  $CodexPackageVersion"
    Write-Host "Target:             $Target"
    Write-Host "SHA256:             $Hash"
    Write-Host "Patch marker count: $MarkerCount"
    Write-Host "Mirror anchor:      $MirrorCount"
    Write-Host "Old append seam:    $AppendOldCount"
    Write-Host "New append seam:    $AppendNewCount"
    Write-Host ""

    if ($MarkerCount -eq 1 -and $MirrorCount -eq 1 -and $AppendOldCount -eq 0 -and $AppendNewCount -eq 1) {
        Write-Host "STATUS: INSTALLED" -ForegroundColor Green
        Write-Host "Future mirrored toolCall rows omit duplicate input when input == arguments."
        Write-Host "Future mirrored toolResult rows omit duplicate inner content when content == text."
    }
    elseif ($MarkerCount -eq 0 -and $MirrorCount -eq 1 -and $AppendOldCount -eq 1 -and $AppendNewCount -eq 0) {
        Write-Host "STATUS: READY TO APPLY" -ForegroundColor Green
        Write-Host "No files changed."
    }
    else {
        Write-Host "STATUS: UNEXPECTED / REFUSE TO PATCH" -ForegroundColor Red
        Write-Host "Do not force the patch. Inspect the runtime first."
    }
    Write-Host ""
}

if ($Action -eq "status") {
    Show-Status
    exit 0
}

if ($Action -eq "rollback") {
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        throw "Rollback manifest missing: $Manifest"
    }
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
        throw "Rollback backup missing: $Backup"
    }

    $M = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ([string]$M.target -ne $Target) {
        throw "Manifest target does not match current target. Refusing rollback."
    }

    $CurrentHash = Get-Sha256 $Target
    $ExpectedPatchedHash = ([string]$M.patchedSha256).ToLowerInvariant()
    if ($CurrentHash -ne $ExpectedPatchedHash) {
        throw "Target changed after V1 was applied. Roll back later patches first; refusing to overwrite newer edits."
    }

    $BackupHash = Get-Sha256 $Backup
    $ExpectedOriginalHash = ([string]$M.originalSha256).ToLowerInvariant()
    if ($BackupHash -ne $ExpectedOriginalHash) {
        throw "Backup hash mismatch. Refusing rollback."
    }

    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    Assert-NodeSyntax $Target

    if ((Get-Sha256 $Target) -ne $ExpectedOriginalHash) {
        throw "Rollback verification failed."
    }

    Write-Host ""
    Write-Host "ROLLBACK PASS" -ForegroundColor Green
    Write-Host "Restored exact pre-V1 provider-capabilities runtime."
    Write-Host "Restart:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
    exit 0
}

# Apply
if ($MarkerCount -eq 1 -and $AppendNewCount -eq 1 -and $AppendOldCount -eq 0) {
    Write-Host "V1 is already installed; no changes made."
    Show-Status
    exit 0
}

if ($MarkerCount -ne 0 -or $MirrorCount -ne 1 -or $AppendOldCount -ne 1 -or $AppendNewCount -ne 0) {
    throw "Preflight failed. Expected marker=0, mirror anchor=1, old append seam=1, new append seam=0. Nothing changed."
}

$Insert = $Helper + "`n" + $MirrorFunctionAnchor
$NewText = $Text.Replace($MirrorFunctionAnchor, $Insert)
if ((Count-Literal $NewText $PatchId) -ne 1) {
    throw "In-memory helper insertion validation failed. Nothing changed."
}

$NewText = $NewText.Replace($AppendOld, $AppendNew)
if ((Count-Literal $NewText $AppendOld) -ne 0 -or (Count-Literal $NewText $AppendNew) -ne 1) {
    throw "In-memory append-seam validation failed. Nothing changed."
}

# Preserve the exact constructors. V1 must not alter live projector/protocol objects.
if ((Count-Literal $NewText 'arguments: args,') -lt 1 -or (Count-Literal $NewText 'input: args') -lt 1) {
    throw "Tool-call constructor compatibility aliases are not intact in memory. Refusing to write."
}
if ((Count-Literal $NewText 'content: text,') -lt 1) {
    throw "Tool-result constructor compatibility alias is not intact in memory. Refusing to write."
}

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
if ((Test-Path -LiteralPath $Backup) -or (Test-Path -LiteralPath $Manifest)) {
    throw "Existing V1 state found at $StateDir. Refusing to overwrite it."
}

$OriginalHash = $Hash
Copy-Item -LiteralPath $Target -Destination $Backup

$Temp = "$Target.$PatchId.tmp.js"
try {
    [System.IO.File]::WriteAllText($Temp, $NewText, [System.Text.UTF8Encoding]::new($false))
    Assert-NodeSyntax $Temp
    Move-Item -LiteralPath $Temp -Destination $Target -Force
    Assert-NodeSyntax $Target

    $Verify = [System.IO.File]::ReadAllText($Target)
    if ((Count-Literal $Verify $PatchId) -ne 1 -or
        (Count-Literal $Verify $AppendNew) -ne 1 -or
        (Count-Literal $Verify $AppendOld) -ne 0) {
        throw "Post-write marker/seam verification failed."
    }

    $PatchedHash = Get-Sha256 $Target

    [ordered]@{
        patch = "Forge Codex Mirror Alias Dedupe V1"
        marker = $PatchId
        openClawVersion = $OpenClawVersion
        codexPackageVersion = $CodexPackageVersion
        target = $Target
        backup = $Backup
        originalSha256 = $OriginalHash
        patchedSha256 = $PatchedHash
        behavior = @(
            "Persisted Codex mirror only: remove toolCall.input iff it is JSON-equivalent to toolCall.arguments.",
            "Persisted Codex mirror only: remove toolResult block.content iff it is a string exactly equal to block.text.",
            "Live tool constructors, tool execution, Codex protocol responses, before_message_write hooks, and non-identical aliases remain untouched."
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Manifest -Encoding UTF8

    Write-Host ""
    Write-Host "APPLY PASS" -ForegroundColor Green
    Write-Host "Original SHA256: $OriginalHash"
    Write-Host "Patched SHA256:  $PatchedHash"
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
    Write-Host ""
    Write-Host "Then perform one harmless tool call and inspect only the NEW JSONL rows."
    Write-Host "Old session rows are intentionally NOT rewritten by this patch."
    Write-Host ""
}
catch {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $Backup) {
        Copy-Item -LiteralPath $Backup -Destination $Target -Force
    }
    throw
}
