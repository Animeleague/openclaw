param(
    [string]$Manifest
)

& {
    $ErrorActionPreference = "Stop"
    $pluginId = "forge-discord-monitor"
    $backupRoot = Join-Path $env:USERPROFILE ".openclaw\backups\forge-rolling-continuity-v5"

    function Read-Utf8Json([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "JSON file not found: $Path"
        }
        return [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
    }

    function Get-Sha256([string]$Path) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    function Assert-BackupHash([string]$Path, [string]$Expected, [string]$Label) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "$Label backup is missing: $Path"
        }
        $actual = Get-Sha256 $Path
        if ($Expected -and $actual -ne $Expected) {
            throw "$Label backup hash mismatch. Expected $Expected, got $actual"
        }
    }

    if (-not $Manifest) {
        if (-not (Test-Path -LiteralPath $backupRoot)) {
            throw "No Forge V5 backup root exists: $backupRoot"
        }
        $Manifest = Get-ChildItem -LiteralPath $backupRoot -Recurse -File -Filter "rollback-manifest.json" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object FullName
    }

    if (-not $Manifest) {
        throw "No rollback manifest was found."
    }

    $Manifest = (Resolve-Path -LiteralPath $Manifest).Path
    $m = Read-Utf8Json $Manifest

    if ($m.schemaVersion -ne 1) {
        throw "Unsupported rollback manifest schema: $($m.schemaVersion)"
    }
    if ($m.pluginId -ne $pluginId) {
        throw "Rollback manifest is for unexpected plugin: $($m.pluginId)"
    }

    Write-Host ""
    Write-Host "Forge Rolling Continuity V5 rollback" -ForegroundColor Yellow
    Write-Host "Manifest: $Manifest"
    Write-Host "Backup created: $($m.createdAt)"
    Write-Host ""

    Assert-BackupHash $m.configBackup $m.configSha256 "OpenClaw config"
    Assert-BackupHash $m.runAttemptBackup $m.runAttemptSha256 "Codex run-attempt bundle"
    Assert-BackupHash $m.pluginBackupPackage $m.pluginBackupPackageSha256 "Forge monitor package"

    $preRollbackDir = Join-Path $m.backupDir ("pre-rollback-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $preRollbackDir | Out-Null

    if (Test-Path -LiteralPath $m.configPath) {
        Copy-Item -LiteralPath $m.configPath -Destination (Join-Path $preRollbackDir "openclaw.v5.json") -Force
    }
    if (Test-Path -LiteralPath $m.runAttemptPath) {
        Copy-Item -LiteralPath $m.runAttemptPath -Destination (Join-Path $preRollbackDir "run-attempt.v5.js") -Force
    }

    try {
        $currentInventory = (& openclaw plugins list --json | Out-String)
        if ($LASTEXITCODE -eq 0 -and $currentInventory.Trim()) {
            [System.IO.File]::WriteAllText(
                (Join-Path $preRollbackDir "plugins-v5.json"),
                $currentInventory,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
    }
    catch {
        Write-Warning "Could not snapshot current plugin inventory before rollback: $($_.Exception.Message)"
    }

    Write-Host "Stopping gateway before rollback..."
    try {
        & openclaw gateway stop
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Gateway stop returned exit code $LASTEXITCODE; continuing with file restore."
        }
    }
    catch {
        Write-Warning "Gateway stop failed; continuing with file restore: $($_.Exception.Message)"
    }

    Write-Host "Restoring pre-V5 OpenClaw config byte-for-byte..."
    Copy-Item -LiteralPath $m.configBackup -Destination $m.configPath -Force
    if ((Get-Sha256 $m.configPath) -ne $m.configSha256) {
        throw "Restored OpenClaw config hash does not match backup."
    }

    Write-Host "Restoring pre-V5 Codex run-attempt bundle byte-for-byte..."
    Copy-Item -LiteralPath $m.runAttemptBackup -Destination $m.runAttemptPath -Force
    if ((Get-Sha256 $m.runAttemptPath) -ne $m.runAttemptSha256) {
        throw "Restored Codex bundle hash does not match backup."
    }

    & node --check $m.runAttemptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Restored Codex bundle failed node --check."
    }

    Write-Host "Reinstalling exact pre-V5 Forge monitor package..."
    & openclaw plugins install "npm-pack:$($m.pluginBackupPackage)" --force
    if ($LASTEXITCODE -ne 0) {
        throw "Pre-V5 monitor package reinstall failed."
    }

    Write-Host "Validating restored configuration..."
    & openclaw config validate
    if ($LASTEXITCODE -ne 0) {
        throw "Restored OpenClaw config failed validation."
    }

    Write-Host "Restarting restored gateway..."
    & openclaw gateway restart
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway restart failed after rollback."
    }

    Write-Host "Checking restored gateway..."
    & openclaw gateway status --deep --require-rpc
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway deep status failed after rollback."
    }

    Write-Host "Inspecting restored monitor runtime..."
    & openclaw plugins inspect $pluginId --runtime --json
    if ($LASTEXITCODE -ne 0) {
        throw "Restored monitor runtime inspection failed."
    }

    Write-Host ""
    Write-Host "PASS - Forge Rolling Continuity V5 fully rolled back." -ForegroundColor Green
    Write-Host "Restored:"
    Write-Host "  Config SHA256:      $($m.configSha256)"
    Write-Host "  Codex SHA256:       $($m.runAttemptSha256)"
    Write-Host "  Monitor package:    $($m.pluginBackupPackage)"
    Write-Host ""
    Write-Host "Pre-rollback V5 safety snapshot:"
    Write-Host "  $preRollbackDir"
}
