param(
    [ValidateSet("status","apply","rollback")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$CodexDist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"
$BackupDir = Join-Path $env:USERPROFILE "Downloads\forge-codex-image-stability-v1_1-backup"
$Manifest  = Join-Path $BackupDir "manifest.json"

$Marker = "FORGE_CODEX_IMAGE_STABILITY_V1_1"

function Find-UniqueSourceFile {
    param(
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not (Test-Path $CodexDist)) {
        throw "Codex dist directory not found: $CodexDist"
    }

    $Matches = @(
        Get-ChildItem $CodexDist -Recurse -File -Filter "*.js" |
        Select-String -SimpleMatch -Pattern $Needle -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -Unique
    )

    if ($Matches.Count -ne 1) {
        throw "Expected exactly 1 $Label source file containing '$Needle', found $($Matches.Count)."
    }

    return $Matches[0]
}

function Resolve-Targets {
    $Inbound = Find-UniqueSourceFile `
        -Needle "function extractInboundMedia(event)" `
        -Label "inbound-media"

    $Vision = Find-UniqueSourceFile `
        -Needle "function filterToolsForVisionInputs(tools, params)" `
        -Label "vision-tool"

    return [pscustomobject]@{
        InboundMediaFile = $Inbound
        VisionToolsFile  = $Vision
    }
}

function Get-State {
    $Targets = Resolve-Targets
    $InboundText = Get-Content $Targets.InboundMediaFile -Raw
    $VisionText  = Get-Content $Targets.VisionToolsFile -Raw

    [pscustomobject]@{
        Targets = $Targets
        InboundPatched = $InboundText.Contains($Marker)
        VisionPatched  = $VisionText.Contains($Marker)
    }
}

function Show-Status {
    $State = Get-State

    Write-Host ""
    Write-Host "Forge Codex Image Stability V1.1"
    Write-Host ""
    Write-Host "Discovered targets:"
    Write-Host "  inbound media: $($State.Targets.InboundMediaFile)"
    Write-Host "  vision tools:  $($State.Targets.VisionToolsFile)"
    Write-Host ""
    Write-Host "Patch state:"
    Write-Host "  inbound media dedupe: $($State.InboundPatched)"
    Write-Host "  image schema stable:  $($State.VisionPatched)"
    Write-Host "  backups exist:        $(Test-Path $Manifest)"
    Write-Host ""

    if ($State.InboundPatched -and $State.VisionPatched) {
        Write-Host "STATUS: INSTALLED"
    }
    elseif ($State.InboundPatched -or $State.VisionPatched) {
        Write-Host "STATUS: PARTIAL - do not restart; rollback or inspect first"
    }
    else {
        Write-Host "STATUS: NOT INSTALLED"
    }
}

function Save-Backups {
    param($Targets)

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    $InboundBackup = Join-Path $BackupDir "inbound-media.original.js"
    $VisionBackup  = Join-Path $BackupDir "vision-tools.original.js"

    if (-not (Test-Path $InboundBackup)) {
        Copy-Item $Targets.InboundMediaFile $InboundBackup
    }
    if (-not (Test-Path $VisionBackup)) {
        Copy-Item $Targets.VisionToolsFile $VisionBackup
    }

    $Data = [ordered]@{
        inboundMediaFile = $Targets.InboundMediaFile
        visionToolsFile  = $Targets.VisionToolsFile
        inboundBackup    = $InboundBackup
        visionBackup     = $VisionBackup
    }

    $Data | ConvertTo-Json | Set-Content $Manifest -Encoding UTF8
}

function Apply-Patch {
    $State = Get-State

    if ($State.InboundPatched -and $State.VisionPatched) {
        Write-Host "Image Stability V1.1 is already installed."
        return
    }

    if ($State.InboundPatched -or $State.VisionPatched) {
        throw "Partial V1.1 patch state detected. Roll back before applying again."
    }

    $Targets = $State.Targets
    Save-Backups $Targets

    $InboundText = Get-Content $Targets.InboundMediaFile -Raw
    $VisionText  = Get-Content $Targets.VisionToolsFile -Raw

    # ------------------------------------------------------------------
    # FIX 1: dedupe legacy singular/plural inbound media aliases.
    # ------------------------------------------------------------------
    $InboundPattern = '(?ms)(function extractInboundMedia\(event\) \{\s*const metadata = event\.metadata \?\? \{\};\s*const paths = normalizeSingleOrTrimmedStringList\(metadata\.mediaPaths\)\.concat\(normalizeSingleOrTrimmedStringList\(metadata\.mediaPath\)\);\s*const urls = normalizeSingleOrTrimmedStringList\(metadata\.mediaUrls\)\.concat\(normalizeSingleOrTrimmedStringList\(metadata\.mediaUrl\)\);\s*const mimeTypes = normalizeSingleOrTrimmedStringList\(metadata\.mediaTypes\)\.concat\(normalizeSingleOrTrimmedStringList\(metadata\.mediaType\)\);\s*const count = Math\.max\(paths\.length, urls\.length, mimeTypes\.length\);\s*)const media = \[\];\s*for \(let index = 0; index < count; index \+= 1\) media\.push\(\{\s*path: paths\[index\],\s*url: urls\[index\],\s*mimeType: mimeTypes\[index\] \?\? mimeTypes\[0\]\s*\}\);\s*return media;'

    $InboundReplacement = @'
$1// FORGE_CODEX_IMAGE_STABILITY_V1_1: dedupe legacy singular/plural media aliases.
	const media = [];
	const seenMedia = /* @__PURE__ */ new Set();
	for (let index = 0; index < count; index += 1) {
		const item = {
			path: paths[index],
			url: urls[index],
			mimeType: mimeTypes[index] ?? mimeTypes[0]
		};
		const dedupeKey = item.path || item.url ? JSON.stringify([item.path ?? null, item.url ?? null]) : null;
		if (dedupeKey && seenMedia.has(dedupeKey)) continue;
		if (dedupeKey) seenMedia.add(dedupeKey);
		media.push(item);
	}
	return media;
'@

    $InboundRegex = [regex]::new($InboundPattern)
    $InboundCount = $InboundRegex.Matches($InboundText).Count

    if ($InboundCount -ne 1) {
        throw "Inbound-media source shape was not exactly as expected (matches=$InboundCount). Nothing was changed."
    }

    $NewInboundText = $InboundRegex.Replace($InboundText, $InboundReplacement, 1)

    # ------------------------------------------------------------------
    # FIX 2: keep the image tool schema stable on image-bearing turns.
    # ------------------------------------------------------------------
    $VisionPattern = '(?ms)function filterToolsForVisionInputs\(tools, params\) \{\s*if \(!params\.modelHasVision \|\| !params\.hasInboundImages\) return tools;\s*return tools\.filter\(\(tool\) => tool\.name !== "image"\);\s*\}'

    $VisionReplacement = @'
function filterToolsForVisionInputs(tools, params) {
	// FORGE_CODEX_IMAGE_STABILITY_V1_1: preserve the dynamic-tool schema
	// across image-bearing turns. Runtime tool policy remains unchanged.
	return tools;
}
'@

    $VisionRegex = [regex]::new($VisionPattern)
    $VisionCount = $VisionRegex.Matches($VisionText).Count

    if ($VisionCount -ne 1) {
        throw "Vision-tool source shape was not exactly as expected (matches=$VisionCount). Nothing was changed."
    }

    $NewVisionText = $VisionRegex.Replace($VisionText, $VisionReplacement, 1)

    # Both matches validated before either runtime file is written.
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Targets.InboundMediaFile, $NewInboundText, $Utf8NoBom)
    [System.IO.File]::WriteAllText($Targets.VisionToolsFile,  $NewVisionText,  $Utf8NoBom)

    $Final = Get-State
    if (-not ($Final.InboundPatched -and $Final.VisionPatched)) {
        throw "Post-write verification failed. Run -Action rollback before restarting."
    }

    Write-Host ""
    Write-Host "IMAGE STABILITY V1.1 APPLY PASS"
    Write-Host ""
    Write-Host "Patched:"
    Write-Host "  1. Codex inbound image/media dedupe"
    Write-Host "  2. Stable image-tool schema on image-bearing turns"
    Write-Host ""
    Write-Host "Discovered runtime files:"
    Write-Host "  $($Targets.InboundMediaFile)"
    Write-Host "  $($Targets.VisionToolsFile)"
    Write-Host ""
    Write-Host "Backup manifest:"
    Write-Host "  $Manifest"
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
}

function Rollback-Patch {
    if (-not (Test-Path $Manifest)) {
        throw "Rollback manifest not found: $Manifest"
    }

    $Data = Get-Content $Manifest -Raw | ConvertFrom-Json

    foreach ($Path in @(
        $Data.inboundMediaFile,
        $Data.visionToolsFile,
        $Data.inboundBackup,
        $Data.visionBackup
    )) {
        if (-not (Test-Path $Path)) {
            throw "Rollback file missing: $Path"
        }
    }

    Copy-Item $Data.inboundBackup $Data.inboundMediaFile -Force
    Copy-Item $Data.visionBackup  $Data.visionToolsFile  -Force

    $InboundText = Get-Content $Data.inboundMediaFile -Raw
    $VisionText  = Get-Content $Data.visionToolsFile -Raw

    if ($InboundText.Contains($Marker) -or $VisionText.Contains($Marker)) {
        throw "Rollback verification failed: V1.1 marker still present."
    }

    Write-Host ""
    Write-Host "IMAGE STABILITY V1.1 ROLLBACK PASS"
    Write-Host ""
    Write-Host "Restart once:"
    Write-Host "  openclaw gateway restart"
}

switch ($Action) {
    "status"   { Show-Status }
    "apply"    { Apply-Patch }
    "rollback" { Rollback-Patch }
}
