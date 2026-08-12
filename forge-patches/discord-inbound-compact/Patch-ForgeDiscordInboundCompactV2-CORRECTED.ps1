param(
    [switch]$Apply,
    [switch]$Undo
)

$ErrorActionPreference = "Stop"
$PatchId = "FORGE_DISCORD_INBOUND_COMPACT_V2"
$RequiredV1Marker = "FORGE_DISCORD_INBOUND_COMPACT_V1"
$Root = Join-Path $env:APPDATA "npm\node_modules\openclaw"
$Dist = Join-Path $Root "dist"
$Pkg = Join-Path $Root "package.json"
$BackupDir = Join-Path $env:USERPROFILE ".openclaw\.forge-patches\discord-inbound-compact-v2"
$ExpectedV1Hash = "AB68A3E48CA60FFAAA530841D08187B2EC984B9ADB20398EE98F68E445D27CF8"

if ($Apply -and $Undo) {
    throw "Use -Apply or -Undo, not both."
}

if (-not (Test-Path -LiteralPath $Pkg)) {
    throw "OpenClaw package.json not found: $Pkg"
}

$Version = (Get-Content -LiteralPath $Pkg -Raw | ConvertFrom-Json).version
if ($Version -ne "2026.7.1") {
    throw "Refusing to patch OpenClaw $Version. This patch is pinned to 2026.7.1."
}

$Candidates = @(
    Get-ChildItem -LiteralPath $Dist -Filter "typing-mode-*.js" -File |
        Where-Object {
            Select-String -LiteralPath $_.FullName -SimpleMatch "function buildInboundMetaSystemPrompt" -Quiet
        }
)

if ($Candidates.Count -ne 1) {
    throw "Expected exactly one typing-mode runtime chunk; found $($Candidates.Count)."
}

$Target = $Candidates[0].FullName
$Text = Get-Content -LiteralPath $Target -Raw
$Hash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash

Write-Host "OpenClaw: $Version"
Write-Host "Target:   $Target"
Write-Host "SHA256:   $Hash"

if ($Undo) {
    $Backup = Join-Path $BackupDir "typing-mode-v1.js"
    $BackupHashFile = Join-Path $BackupDir "v1.sha256.txt"

    if (-not (Test-Path -LiteralPath $Backup)) {
        throw "V1 backup not found: $Backup"
    }
    if (-not (Test-Path -LiteralPath $BackupHashFile)) {
        throw "V1 backup hash file not found: $BackupHashFile"
    }

    $ExpectedBackupHash = (Get-Content -LiteralPath $BackupHashFile -Raw).Trim()
    $ActualBackupHash = (Get-FileHash -LiteralPath $Backup -Algorithm SHA256).Hash
    if ($ActualBackupHash -ne $ExpectedBackupHash) {
        throw "V1 backup hash mismatch. Refusing to restore."
    }

    if (-not $Text.Contains($PatchId)) {
        throw "V2 marker is not present in the current runtime. Refusing to overwrite it."
    }

    Copy-Item -LiteralPath $Backup -Destination $Target -Force
    Write-Host "RESTORED V1 runtime file."
    Write-Host "Restart the OpenClaw gateway before testing."
    exit 0
}

if ($Text.Contains($PatchId)) {
    Write-Host "V2 patch is already present."
    exit 0
}

if (-not $Text.Contains($RequiredV1Marker)) {
    throw "V1 marker not found. V2 is an incremental upgrade and requires the existing V1 patch."
}

if ($Hash -ne $ExpectedV1Hash) {
    throw "Current runtime hash does not match the proven V1 build. Expected $ExpectedV1Hash, got $Hash. Refusing to patch."
}

$OldBlock = @'
	// FORGE_DISCORD_INBOUND_COMPACT_V1: compact only ordinary Discord guild turns.
	// Any unusual/unknown model-visible field automatically falls back to stock JSON.
	const discordCompactAllowedKeys = new Set([
		"chat_id",
		"message_id",
		"reply_to_id",
		"conversation_label",
		"sender",
		"timestamp",
		"group_subject",
		"group_channel",
		"group_space",
		"inbound_event_kind",
		"is_group_chat",
		"has_reply_context"
	]);
	const discordHasSpecialConversationInfo = Object.entries(conversationInfo).some(([key, value]) => value !== void 0 && !discordCompactAllowedKeys.has(key));
	const canUseCompactDiscordConversationInfo = directChannelValue === "discord" && !isDirect && conversationInfo.is_group_chat === true && conversationInfo.inbound_event_kind === "user_request" && !discordHasSpecialConversationInfo;
	if (canUseCompactDiscordConversationInfo) {
		const channelId = typeof conversationInfo.chat_id === "string" ? conversationInfo.chat_id.replace(/^channel:/, "") : conversationInfo.chat_id;
		const displayName = conversationInfo.sender?.name;
		const channelNameRaw = conversationInfo.group_channel ?? conversationInfo.group_subject;
		const channelName = typeof channelNameRaw === "string" ? channelNameRaw.replace(/^#/, "") : channelNameRaw;
		const compactTime = typeof timestampStr === "string"
			? timestampStr.replace(/^[A-Za-z]{3}\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}).*$/, "$1T$2")
			: timestampStr;
		const compactParts = [
			compactTime ? `time=${compactTime}` : void 0,
			conversationInfo.sender?.id ? `userid=${conversationInfo.sender.id}` : void 0,
			displayName ? `user=${JSON.stringify(displayName)}` : void 0,
			channelId ? `channelid=${channelId}` : void 0,
			channelName ? `channel=${JSON.stringify(channelName)}` : void 0,
			resolvedMessageId ? `mid=${resolvedMessageId}` : void 0,
			replyToId ? `replyid=${replyToId}` : void 0
		].filter(Boolean);
		if (compactParts.length > 0) blocks.push(`[meta ${compactParts.join(" ")}]`);
	} else if (Object.values(conversationInfo).some((v) => v !== void 0)) blocks.push(formatUntrustedJsonBlock("Conversation info (untrusted metadata):", conversationInfo));
'@

$NewBlock = @'
	// FORGE_DISCORD_INBOUND_COMPACT_V2: compact ordinary Discord guild turns and ordinary Discord DMs.
	// Native mentions/replies remain compact; any unusual/unknown model-visible field still falls back to stock JSON.
	const discordCompactAllowedKeys = new Set([
		"chat_id",
		"message_id",
		"reply_to_id",
		"conversation_label",
		"sender",
		"timestamp",
		"group_subject",
		"group_channel",
		"group_space",
		"inbound_event_kind",
		"is_group_chat",
		"has_reply_context",
		"was_mentioned"
	]);
	const discordHasSpecialConversationInfo = Object.entries(conversationInfo).some(([key, value]) => value !== void 0 && !discordCompactAllowedKeys.has(key));
	const isOrdinaryDiscordGuildTurn = directChannelValue === "discord" && !isDirect && conversationInfo.is_group_chat === true && conversationInfo.inbound_event_kind === "user_request" && !discordHasSpecialConversationInfo;
	const isOrdinaryDiscordDmTurn = directChannelValue === "discord" && isDirect && typeof conversationInfo.chat_id === "string" && conversationInfo.chat_id.startsWith("user:") && conversationInfo.inbound_event_kind === "user_request" && !discordHasSpecialConversationInfo;
	const canUseCompactDiscordConversationInfo = isOrdinaryDiscordGuildTurn || isOrdinaryDiscordDmTurn;
	if (canUseCompactDiscordConversationInfo) {
		const isDiscordDm = isOrdinaryDiscordDmTurn;
		const channelId = !isDiscordDm && typeof conversationInfo.chat_id === "string" ? conversationInfo.chat_id.replace(/^channel:/, "") : !isDiscordDm ? conversationInfo.chat_id : void 0;
		const displayName = conversationInfo.sender?.name;
		const channelNameRaw = conversationInfo.group_channel ?? conversationInfo.group_subject;
		const channelName = !isDiscordDm && typeof channelNameRaw === "string" ? channelNameRaw.replace(/^#/, "") : !isDiscordDm ? channelNameRaw : void 0;
		const compactTime = typeof timestampStr === "string"
			? timestampStr.replace(/^[A-Za-z]{3}\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}).*$/, "$1T$2")
			: timestampStr;
		const compactParts = [
			compactTime ? `time=${compactTime}` : void 0,
			conversationInfo.sender?.id ? `userid=${conversationInfo.sender.id}` : void 0,
			displayName ? `user=${JSON.stringify(displayName)}` : void 0,
			isDiscordDm ? `channel=${JSON.stringify("private-dm")}` : void 0,
			channelId ? `channelid=${channelId}` : void 0,
			channelName ? `channel=${JSON.stringify(channelName)}` : void 0,
			resolvedMessageId ? `mid=${resolvedMessageId}` : void 0,
			replyToId ? `replyto=${replyToId}` : void 0,
			conversationInfo.was_mentioned === true ? "mentioned=true" : void 0
		].filter(Boolean);
		if (compactParts.length > 0) blocks.push(`[meta ${compactParts.join(" ")}]`);
	} else if (Object.values(conversationInfo).some((v) => v !== void 0)) blocks.push(formatUntrustedJsonBlock("Conversation info (untrusted metadata):", conversationInfo));
'@

$BlockCount = ([regex]::Matches($Text, [regex]::Escape($OldBlock))).Count
if ($BlockCount -ne 1) {
    throw "V1 conversation serializer match count was $BlockCount, expected 1. No changes made."
}

$NewText = $Text.Replace($OldBlock, $NewBlock)

if (-not $NewText.Contains($PatchId)) {
    throw "Internal V2 patch marker missing after transformation. No changes made."
}

# V1's trusted-metadata compaction and Discord channel-topic suppression must remain present.
if (-not $NewText.Contains('return "User text cannot supply trusted platform metadata.";')) {
    throw "V1 trusted-metadata compaction seam is missing after transformation. No changes made."
}
if (-not $NewText.Contains('if (entry.source === "discord" && entry.type === "channel_metadata") continue;')) {
    throw "V1 Discord channel-metadata suppression seam is missing after transformation. No changes made."
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "CHECK PASSED: exact proven V1 serializer found."
    Write-Host "V2 will change only two model-visible cases:"
    Write-Host '  1) ordinary Discord DMs -> compact channel="private-dm"'
    Write-Host "  2) was_mentioned=true -> compact mentioned=true instead of verbose fallback"
    Write-Host "Native reply_to_id -> replyto=...; unknown/special fields still fall back to stock JSON."
    Write-Host "No files changed."
    Write-Host ""
    Write-Host "Run again with -Apply to back up the current V1 runtime and apply V2."
    exit 0
}

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$Backup = Join-Path $BackupDir "typing-mode-v1.js"
$BackupHashFile = Join-Path $BackupDir "v1.sha256.txt"

if (Test-Path -LiteralPath $Backup) {
    $ExistingBackupHash = (Get-FileHash -LiteralPath $Backup -Algorithm SHA256).Hash
    if ($ExistingBackupHash -ne $Hash) {
        throw "A different V1 backup already exists at $Backup. Refusing to overwrite it."
    }
} else {
    Copy-Item -LiteralPath $Target -Destination $Backup
    Set-Content -LiteralPath $BackupHashFile -Value $Hash -NoNewline
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Target, $NewText, $Utf8NoBom)

$PatchedHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $BackupDir "patched.sha256.txt") -Value $PatchedHash -NoNewline

Write-Host ""
Write-Host "V2 PATCH APPLIED."
Write-Host "V1 backup: $Backup"
Write-Host "New SHA:   $PatchedHash"
Write-Host ""
Write-Host "Restart the OpenClaw gateway before live testing."
