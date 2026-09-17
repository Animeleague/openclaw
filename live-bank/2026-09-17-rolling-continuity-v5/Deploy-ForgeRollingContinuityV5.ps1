# Deploy Forge Rolling Continuity V5
# Full pre-change backup + automatic rollback on any post-backup deployment failure.
# Uses a detached temporary worktree so the existing local monitor working copy is untouched.

& {
    $ErrorActionPreference = "Stop"

    $pluginId = "forge-discord-monitor"
    $repo = Join-Path $env:USERPROFILE "Desktop\forge-discord-monitor-v1.1.3"
    $remoteBranch = "wip/2026-09-17-rolling-continuity-v5"
    $patchScript = Join-Path $PSScriptRoot "Patch-ForgeRollingContinuityV5.ps1"
    $rollbackScript = Join-Path $PSScriptRoot "Rollback-ForgeRollingContinuityV5.ps1"

    $cfg = Join-Path $env:USERPROFILE ".openclaw\openclaw.json"
    $projectDist = Join-Path $env:USERPROFILE ".openclaw\npm\projects\openclaw-codex-8902d781d4\node_modules\@openclaw\codex\dist"

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $worktree = Join-Path $env:TEMP "forge-rolling-v5-$stamp"
    $packDir = Join-Path $env:TEMP "forge-rolling-v5-pack-$stamp"
    $backupRoot = Join-Path $env:USERPROFILE ".openclaw\backups\forge-rolling-continuity-v5"
    $backupDir = Join-Path $backupRoot $stamp
    $manifestPath = Join-Path $backupDir "rollback-manifest.json"
    $backupReady = $false

    function Write-Utf8NoBom([string]$Path, [string]$Text) {
        [System.IO.File]::WriteAllText(
            $Path,
            $Text,
            [System.Text.UTF8Encoding]::new($false)
        )
    }

    function Get-Sha256([string]$Path) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    function Resolve-HomePath([string]$Path) {
        if (-not $Path) { return $Path }
        if ($Path -eq "~") { return $env:USERPROFILE }
        if ($Path.StartsWith("~\") -or $Path.StartsWith("~/")) {
            return Join-Path $env:USERPROFILE $Path.Substring(2)
        }
        return [Environment]::ExpandEnvironmentVariables($Path)
    }

    foreach ($required in @($repo, $cfg, $projectDist, $patchScript, $rollbackScript)) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required path not found: $required"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repo ".git"))) {
        throw "Monitor path is not a Git working copy: $repo"
    }

    $dirty = @(& git -C $repo status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read monitor repo status."
    }
    if ($dirty.Count -gt 0) {
        throw "Existing monitor working copy has local changes. Refusing to touch it."
    }

    $runAttempt = @(
        Get-ChildItem -LiteralPath $projectDist -File -Filter "run-attempt-*.js" |
            Where-Object {
                Select-String -LiteralPath $_.FullName -Pattern "FORGE_CODEX_NATIVE_POSTTURN_HARDCAP_NATIVE_V3" -Quiet
            }
    ) | Select-Object -First 1

    if (-not $runAttempt) {
        throw "Could not find active Codex run-attempt bundle with Forge hardcap marker."
    }
    $runAttemptPath = $runAttempt.FullName

    New-Item -ItemType Directory -Force -Path $packDir | Out-Null
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    try {
        Write-Host ""
        Write-Host "Creating full pre-V5 rollback snapshot..." -ForegroundColor Cyan

        $configBackup = Join-Path $backupDir "openclaw.pre-v5.json"
        $runAttemptBackup = Join-Path $backupDir ("pre-v5-" + (Split-Path -Leaf $runAttemptPath))
        Copy-Item -LiteralPath $cfg -Destination $configBackup -Force
        Copy-Item -LiteralPath $runAttemptPath -Destination $runAttemptBackup -Force

        $configSha256 = Get-Sha256 $configBackup
        $runAttemptSha256 = Get-Sha256 $runAttemptBackup

        Write-Host "Creating verified OpenClaw config backup..."
        $officialConfigBackupDir = Join-Path $backupDir "openclaw-official-config-backup"
        New-Item -ItemType Directory -Force -Path $officialConfigBackupDir | Out-Null
        & openclaw backup create --only-config --verify --output $officialConfigBackupDir
        if ($LASTEXITCODE -ne 0) {
            throw "Official OpenClaw config backup failed verification."
        }

        Write-Host "Reading current plugin inventory..."
        $inventoryText = (& openclaw plugins list --json | Out-String)
        if ($LASTEXITCODE -ne 0 -or -not $inventoryText.Trim()) {
            throw "Could not read current OpenClaw plugin inventory."
        }
        Write-Utf8NoBom (Join-Path $backupDir "plugins-before-v5.json") $inventoryText

        $inventory = $inventoryText | ConvertFrom-Json
        $pluginRecord = @($inventory.plugins) |
            Where-Object { $_.id -eq $pluginId } |
            Select-Object -First 1

        if (-not $pluginRecord) {
            throw "Installed plugin record not found for $pluginId."
        }

        $pluginRoot = Resolve-HomePath ([string]$pluginRecord.rootDir)
        if (-not $pluginRoot) {
            $source = Resolve-HomePath ([string]$pluginRecord.source)
            if ($source -and (Test-Path -LiteralPath $source -PathType Leaf)) {
                $pluginRoot = Split-Path -Parent $source
            }
            elseif ($source -and (Test-Path -LiteralPath $source -PathType Container)) {
                $pluginRoot = $source
            }
        }

        if (-not $pluginRoot -or -not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
            throw "Could not resolve installed monitor plugin root from OpenClaw inventory."
        }

        $pluginRoot = (Resolve-Path -LiteralPath $pluginRoot).Path
        Write-Host "Installed monitor root:"
        Write-Host "  $pluginRoot"

        Write-Host "Copying complete installed monitor directory..."
        $pluginSnapshot = Join-Path $backupDir "plugin-root-pre-v5"
        Copy-Item -LiteralPath $pluginRoot -Destination $pluginSnapshot -Recurse -Force

        Write-Host "Packing exact installed pre-V5 monitor package..."
        $oldPackDir = Join-Path $backupDir "pre-v5-monitor-package"
        New-Item -ItemType Directory -Force -Path $oldPackDir | Out-Null
        Push-Location $pluginRoot
        try {
            & npm pack --ignore-scripts --pack-destination $oldPackDir
            if ($LASTEXITCODE -ne 0) {
                throw "Could not pack currently installed pre-V5 monitor."
            }
        }
        finally {
            Pop-Location
        }

        $pluginBackupPackage = Get-ChildItem -LiteralPath $oldPackDir -File -Filter "*.tgz" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $pluginBackupPackage) {
            throw "No pre-V5 monitor backup package was produced."
        }
        $pluginBackupPackageSha256 = Get-Sha256 $pluginBackupPackage.FullName

        try {
            $runtimeBefore = (& openclaw plugins inspect $pluginId --runtime --json | Out-String)
            if ($LASTEXITCODE -eq 0 -and $runtimeBefore.Trim()) {
                Write-Utf8NoBom (Join-Path $backupDir "plugin-runtime-before-v5.json") $runtimeBefore
            }
        }
        catch {
            Write-Warning "Runtime snapshot failed; package/config/Codex backup remains complete."
        }

        Copy-Item -LiteralPath $rollbackScript -Destination (Join-Path $backupDir "Rollback-ForgeRollingContinuityV5.ps1") -Force
        Copy-Item -LiteralPath $patchScript -Destination (Join-Path $backupDir "Patch-ForgeRollingContinuityV5.ps1") -Force

        Write-Host "Fetching reviewed V5 branch..."
        & git -C $repo fetch origin $remoteBranch
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed."
        }
        $deployCommit = (& git -C $repo rev-parse "origin/$remoteBranch").Trim()
        if ($LASTEXITCODE -ne 0 -or -not $deployCommit) {
            throw "Could not resolve V5 branch commit."
        }

        $manifest = [ordered]@{
            schemaVersion = 1
            createdAt = (Get-Date).ToString("o")
            backupDir = $backupDir
            pluginId = $pluginId
            pluginEnabledBefore = [bool]$pluginRecord.enabled
            pluginVersionBefore = [string]$pluginRecord.version
            pluginPackageVersionBefore = [string]$pluginRecord.packageVersion
            pluginRootBefore = $pluginRoot
            pluginSnapshot = $pluginSnapshot
            pluginBackupPackage = $pluginBackupPackage.FullName
            pluginBackupPackageSha256 = $pluginBackupPackageSha256
            configPath = $cfg
            configBackup = $configBackup
            configSha256 = $configSha256
            officialConfigBackupDir = $officialConfigBackupDir
            runAttemptPath = $runAttemptPath
            runAttemptBackup = $runAttemptBackup
            runAttemptSha256 = $runAttemptSha256
            deployBranch = $remoteBranch
            deployCommit = $deployCommit
        }
        Write-Utf8NoBom $manifestPath ($manifest | ConvertTo-Json -Depth 6)

        $null = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        $backupReady = $true

        $rollbackCopy = Join-Path $backupDir "Rollback-ForgeRollingContinuityV5.ps1"
        Write-Host ""
        Write-Host "FULL BACKUP PASS" -ForegroundColor Green
        Write-Host "Backup directory:"
        Write-Host "  $backupDir"
        Write-Host "Rollback manifest:"
        Write-Host "  $manifestPath"
        Write-Host "Pre-V5 config SHA256:"
        Write-Host "  $configSha256"
        Write-Host "Pre-V5 Codex SHA256:"
        Write-Host "  $runAttemptSha256"
        Write-Host "Pre-V5 monitor package SHA256:"
        Write-Host "  $pluginBackupPackageSha256"
        Write-Host ""

        Write-Host "Creating detached V5 worktree..."
        & git -C $repo worktree add --detach $worktree "origin/$remoteBranch"
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add failed."
        }

        Push-Location $worktree
        try {
            Write-Host "Installing exact V5 dependencies..."
            & npm ci
            if ($LASTEXITCODE -ne 0) {
                throw "npm ci failed."
            }

            Write-Host "Running full V5 monitor check..."
            & npm run check
            if ($LASTEXITCODE -ne 0) {
                throw "npm run check failed."
            }

            Write-Host "Packing tested V5 monitor plugin..."
            & npm pack --pack-destination $packDir
            if ($LASTEXITCODE -ne 0) {
                throw "npm pack failed."
            }
        }
        finally {
            Pop-Location
        }

        $package = Get-ChildItem -LiteralPath $packDir -File -Filter "*.tgz" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $package) {
            throw "No tested V5 monitor package was produced."
        }

        Write-Host "Installing tested V5 monitor package:"
        Write-Host "  $($package.FullName)"
        & openclaw plugins install "npm-pack:$($package.FullName)" --force
        if ($LASTEXITCODE -ne 0) {
            throw "OpenClaw V5 monitor plugin install failed."
        }

        & openclaw plugins enable $pluginId
        if ($LASTEXITCODE -ne 0) {
            throw "Could not enable $pluginId."
        }

        Write-Host "Applying guarded Codex V5 patch..."
        & powershell -NoProfile -ExecutionPolicy Bypass -File $patchScript
        if ($LASTEXITCODE -ne 0) {
            throw "Rolling-continuity live patch failed."
        }

        Write-Host "Validating V5 OpenClaw config..."
        & openclaw config validate
        if ($LASTEXITCODE -ne 0) {
            throw "V5 OpenClaw config validation failed."
        }

        Write-Host "Restarting V5 gateway..."
        & openclaw gateway restart
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway restart failed."
        }

        Write-Host "Checking V5 gateway..."
        & openclaw gateway status --deep --require-rpc
        if ($LASTEXITCODE -ne 0) {
            throw "Gateway deep status failed."
        }

        Write-Host "Inspecting V5 monitor runtime..."
        & openclaw plugins inspect $pluginId --runtime --json
        if ($LASTEXITCODE -ne 0) {
            throw "V5 monitor runtime inspection failed."
        }

        Write-Host ""
        Write-Host "PASS - Forge Rolling Continuity V5 deployed." -ForegroundColor Green
        Write-Host "Policy:"
        Write-Host "  Sol native rollover: 80k"
        Write-Host "  Fresh Sol canon history: max ~20k tokens"
        Write-Host "  Fresh Luna canon replay: disabled"
        Write-Host "  Luna rebuilds from retained eligible Sol native journal"
        Write-Host "  Sol -> Luna native delta count cap: none"
        Write-Host "  Journal rolls with Sol native generation"
        Write-Host "  Assistance reason context: disabled"
        Write-Host ""
        Write-Host "FULL ROLLBACK COMMAND:" -ForegroundColor Yellow
        Write-Host ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $rollbackCopy + '" -Manifest "' + $manifestPath + '"')
        Write-Host ""
        Write-Host "Backup directory:"
        Write-Host "  $backupDir"
    }
    catch {
        $deployError = $_
        Write-Host ""
        Write-Host "V5 DEPLOYMENT FAILED: $($deployError.Exception.Message)" -ForegroundColor Red

        if ($backupReady) {
            $rollbackCopy = Join-Path $backupDir "Rollback-ForgeRollingContinuityV5.ps1"
            Write-Host "A verified pre-V5 backup exists. Running automatic rollback now..." -ForegroundColor Yellow
            try {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $rollbackCopy -Manifest $manifestPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Rollback script returned exit code $LASTEXITCODE."
                }
                Write-Host "Automatic rollback completed successfully." -ForegroundColor Green
            }
            catch {
                Write-Host "AUTOMATIC ROLLBACK FAILED: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Manual rollback command:" -ForegroundColor Yellow
                Write-Host ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $rollbackCopy + '" -Manifest "' + $manifestPath + '"')
                throw
            }
        }

        throw $deployError
    }
    finally {
        if (Test-Path -LiteralPath $worktree) {
            & git -C $repo worktree remove --force $worktree 2>$null
        }
    }
}
