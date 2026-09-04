#Requires -Version 7.0
<#
.SYNOPSIS
  OpenClaw managed-component adapter — structured status/update for AI routing.
.DESCRIPTION
  -Status -Json: emit managed_component_status.v1 (read-only, no restart).
  -Update -Json: emit managed_component_update_receipt.v1 (atomic backup->update->wait->verify).
  -ResultPath <path>: also write JSON atomically to file (for UAC capture; see plan §2.6a).
  All human diagnostics go to stderr; stdout is exactly one JSON document.
  Exit code: 0 only when overall succeeded; non-zero for failed/partial.
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Update,
    [switch]$Json,
    [string]$ResultPath,
    [string]$BackupScript = (Join-Path $PSScriptRoot 'backup-config.ps1'),
    [string]$RestoreScript = (Join-Path $PSScriptRoot 'restore-config.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

. (Join-Path $PSScriptRoot '_update_lib.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

$componentId = 'openclaw'
$observedUtc = [DateTime]::UtcNow.ToString('o')

function Get-OcOfficialTargetVersion {
    $run = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @(
        'update', 'status', '--json', '--timeout', '30'
    ) -TimeoutSec 60
    if ($run.TimedOut -or $run.ExitCode -ne 0) { return $null }
    try {
        $status = $run.Stdout | ConvertFrom-Json -Depth 20
        $target = [string]$status.availability.latestVersion
        if (-not $target) { $target = [string]$status.update.registry.latestVersion }
        return Get-OpenClawVersionToken -Text $target
    } catch { return $null }
}

if (($Status -and $Update) -or (-not $Status -and -not $Update)) {
    [Console]::Error.WriteLine("Usage: -Status -Json | -Update -Json [-ResultPath <path>]")
    exit 3
}

# ============================================================
#  Status: -Status -Json
# ============================================================
function Invoke-Status {
    $channel = 'stable'
    $channelResolveOk = $true
    try {
        $chRaw = Get-OCConfigValue -Key 'update.channel'
        if ($chRaw) {
            $chTrim = $chRaw.Trim().ToLowerInvariant()
            if ($chTrim -in @('stable', 'beta', 'dev', 'extended-stable')) {
                $channel = $chTrim
            } elseif ($chTrim) {
                $channelResolveOk = $false
                $channel = 'unknown'
            }
        }
    } catch {
        $channelResolveOk = $false
        $channel = 'unknown'
    }

    $tag = ConvertTo-NpmTag -Channel $channel

    $currentVersion = $null
    $currentProbeOk = $false
    try {
        $verRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('--version') -TimeoutSec 30
        $currentProbeOk = ($verRun.ExitCode -eq 0)
        $currentVersion = Get-OpenClawVersionToken -Text $verRun.Stdout
    } catch {
        $currentProbeOk = $false
    }

    $targetVersion = $null
    $targetProbeOk = $false
    try {
        $targetVersion = Get-OcOfficialTargetVersion
        $targetProbeOk = -not [string]::IsNullOrWhiteSpace($targetVersion)
    } catch {
        $targetProbeOk = $false
    }

    $health = 'unknown'
    try {
        if (Test-OcGatewayHealth) { $health = 'healthy' } else { $health = 'degraded' }
    } catch {
        $health = 'unknown'
    }

    $relation = Get-VersionRelation `
        -CurrentVersion $currentVersion `
        -TargetVersion $targetVersion `
        -CurrentProbeOk $currentProbeOk `
        -TargetProbeOk $targetProbeOk `
        -Channel $channel `
        -ChannelResolveOk $channelResolveOk

    $result = [ordered]@{
        schema           = 'managed_component_status.v1'
        component_id     = $componentId
        observed_utc     = $observedUtc
        current_version  = $currentVersion
        target_version   = $targetVersion
        channel          = $channel
        relation         = $relation
        current_probe_ok = $currentProbeOk
        target_probe_ok  = $targetProbeOk
        health           = $health
        notes            = @()
    }

    if ($Json) {
        Write-JsonResult -Data $result -ResultPath $ResultPath
    } else {
        $result | Format-List | Out-String | Write-Output
    }
    exit 0
}

# ============================================================
#  Backup wrapper: machine-readable result (plan §4a)
# ============================================================
function Invoke-Backup {
    param([string]$BackupScriptPath)
    $backupResult = [ordered]@{ ok = $false; backup_path = $null; error = $null }

    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = (Join-Path $PSHOME 'pwsh.exe')
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-ExecutionPolicy')
        $psi.ArgumentList.Add('Bypass')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($BackupScriptPath)
        $psi.ArgumentList.Add('-Json')
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
        $proc = [Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $waited = $proc.WaitForExit(120000)
        if (-not $waited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            try { $proc.WaitForExit() } catch {}
            $backupResult.error = 'backup timeout (120s)'
            return $backupResult
        }
        $proc.WaitForExit()
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if ($proc.ExitCode -ne 0) {
            $backupResult.error = "backup exit code $($proc.ExitCode): $($stderr.Trim())"
            return $backupResult
        }
        try {
            $parsed = $stdout | ConvertFrom-Json
        } catch {
            $backupResult.error = "backup returned invalid JSON: $_"
            return $backupResult
        }
        if ($parsed.schema -ne 'openclaw_backup_result.v1' -or $parsed.ok -ne $true -or -not $parsed.backup_path) {
            $backupResult.error = 'backup result is missing schema/ok/backup_path'
            return $backupResult
        }
        if (-not (Test-Path -LiteralPath ([string]$parsed.backup_path))) {
            $backupResult.error = "backup path does not exist: $($parsed.backup_path)"
            return $backupResult
        }
        $backupResult.ok = $true
        $backupResult.backup_path = [string]$parsed.backup_path
        return $backupResult
    }
    catch {
        $backupResult.error = "backup execution failed: $_"
        return $backupResult
    }
}

# ============================================================
#  Verify: run all invariant checks, return failed_checks array
# ============================================================
function Invoke-Verify {
    param(
        [string]$ExpectedVersion,
        [string]$InstalledVersion
    )
    $failed = @()

    if ($InstalledVersion -ne $ExpectedVersion) {
        $failed += "version_mismatch: installed=$InstalledVersion expected=$ExpectedVersion"
    }

    $configRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @(
        'config', 'validate', '--json'
    ) -TimeoutSec 30
    try { $configValid = $configRun.ExitCode -eq 0 -and ($configRun.Stdout | ConvertFrom-Json).valid -eq $true }
    catch { $configValid = $false }
    if (-not $configValid) {
        $failed += 'config_schema_invalid'
    }

    $rpcRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @(
        'gateway', 'status', '--require-rpc', '--json'
    ) -TimeoutSec 30
    try { $rpcOk = $rpcRun.ExitCode -eq 0 -and ($rpcRun.Stdout | ConvertFrom-Json).rpc.ok -eq $true }
    catch { $rpcOk = $false }
    if (-not $rpcOk) {
        $failed += 'gateway_rpc_unavailable'
    }

    # Read the current model status and catalog. Both are read-only: they neither
    # send a model request nor change routing, credentials, or gateway state.
    $modelsStatus = $null
    try {
        $modelsRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @(
            'models', 'status', '--json'
        ) -TimeoutSec 30
        if ($modelsRun.TimedOut -or $modelsRun.ExitCode -ne 0) {
            throw 'openclaw models status --json failed'
        }
        $modelsStatus = $modelsRun.Stdout | ConvertFrom-Json -Depth 40
        if ($null -eq $modelsStatus) {
            throw 'openclaw models status --json returned null'
        }
    } catch {
        $failed += 'models_status_unavailable'
    }

    $modelsDirectory = $null
    try {
        $modelsDirectoryRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @(
            'models', 'list', '--json'
        ) -TimeoutSec 30
        if ($modelsDirectoryRun.TimedOut -or $modelsDirectoryRun.ExitCode -ne 0) {
            throw 'openclaw models list --json failed'
        }
        $modelsDirectory = $modelsDirectoryRun.Stdout | ConvertFrom-Json -Depth 40
        if ($null -eq $modelsDirectory) {
            throw 'openclaw models list --json returned null'
        }
    } catch {
        $failed += 'models_directory_unavailable'
    }

    if ($null -ne $modelsStatus) {
        $defaultModelProperty = $modelsStatus.PSObject.Properties['defaultModel']
        $defaultModel = if ($null -ne $defaultModelProperty) {
            [string]$defaultModelProperty.Value
        } else {
            ''
        }
        if ([string]::IsNullOrWhiteSpace($defaultModel)) {
            $failed += 'model_default_missing'
        }

        $allowed = @()
        $allowedProperty = $modelsStatus.PSObject.Properties['allowed']
        if ($null -ne $allowedProperty -and $null -ne $allowedProperty.Value) {
            $allowed = @(
                $allowedProperty.Value |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
        if ($allowed.Count -eq 0) {
            $failed += 'model_allowed_routes_missing'
        }
        if (-not [string]::IsNullOrWhiteSpace($defaultModel) -and
            -not ($allowed -ccontains $defaultModel)) {
            $failed += "model_default_route_missing: $defaultModel"
        }

        if (-not [string]::IsNullOrWhiteSpace($defaultModel)) {
            $defaultProvider = ''
            if ($defaultModel -match '^([^/]+)/') {
                $defaultProvider = $Matches[1]
            }

            $localDefault = $false
            if ($null -ne $modelsDirectory) {
                $directoryEntries = @()
                $directoryModelsProperty = $modelsDirectory.PSObject.Properties['models']
                if ($null -ne $directoryModelsProperty -and $null -ne $directoryModelsProperty.Value) {
                    $directoryEntries = @($directoryModelsProperty.Value)
                } elseif ($modelsDirectory -is [Array]) {
                    $directoryEntries = @($modelsDirectory)
                } else {
                    $directoryEntries = @($modelsDirectory)
                }

                foreach ($directoryEntry in $directoryEntries) {
                    if ($null -eq $directoryEntry) { continue }
                    $keyProperty = $directoryEntry.PSObject.Properties['key']
                    if ($null -eq $keyProperty -or [string]$keyProperty.Value -cne $defaultModel) {
                        continue
                    }
                    $localProperty = $directoryEntry.PSObject.Properties['local']
                    if ($null -ne $localProperty -and $localProperty.Value -is [bool] -and $localProperty.Value) {
                        $localDefault = $true
                    }
                    break
                }
            }

            if (-not $localDefault) {
                $authProviders = @()
                $authProperty = $modelsStatus.PSObject.Properties['auth']
                if ($null -ne $authProperty -and $null -ne $authProperty.Value) {
                    $providersProperty = $authProperty.Value.PSObject.Properties['providers']
                    if ($null -ne $providersProperty -and $null -ne $providersProperty.Value) {
                        $authProviders = @($providersProperty.Value)
                    }
                }

                $hasUsableAuth = $false
                foreach ($providerStatus in $authProviders) {
                    if ($null -eq $providerStatus) { continue }
                    $providerProperty = $providerStatus.PSObject.Properties['provider']
                    $providerName = if ($null -ne $providerProperty) {
                        [string]$providerProperty.Value
                    } else {
                        ''
                    }
                    if ($providerName -cne $defaultProvider) { continue }

                    $profileCount = 0
                    $profilesProperty = $providerStatus.PSObject.Properties['profiles']
                    if ($null -ne $profilesProperty -and $null -ne $profilesProperty.Value) {
                        $profileCountProperty = $profilesProperty.Value.PSObject.Properties['count']
                        if ($null -ne $profileCountProperty) {
                            try { $profileCount = [int]$profileCountProperty.Value }
                            catch { $profileCount = 0 }
                        }
                    }

                    $effectiveKind = ''
                    $effectiveProperty = $providerStatus.PSObject.Properties['effective']
                    if ($null -ne $effectiveProperty -and $null -ne $effectiveProperty.Value) {
                        $kindProperty = $effectiveProperty.Value.PSObject.Properties['kind']
                        if ($null -ne $kindProperty) {
                            $effectiveKind = [string]$kindProperty.Value
                        }
                    }

                    if ($profileCount -gt 0 -or $effectiveKind -in @('env', 'profiles', 'oauth', 'token', 'api_key')) {
                        $hasUsableAuth = $true
                        break
                    }
                }

                if (-not $hasUsableAuth) {
                    $providerLabel = if ($defaultProvider) { $defaultProvider } else { 'unknown' }
                    $failed += "default_provider_auth_missing: $providerLabel"
                }
            }
        }
    }

    $checkOnStart = Get-OCConfigValue -Key 'update.checkOnStart'
    if ($checkOnStart -ne 'false') {
        $failed += "checkOnStart: expected false, got $checkOnStart"
    }

    $autoUpdate = Get-OCConfigValue -Key 'update.auto'
    $autoDisabled = $autoUpdate -eq 'false'
    if ($autoUpdate -and -not $autoDisabled) {
        try { $autoDisabled = ($autoUpdate | ConvertFrom-Json).enabled -eq $false }
        catch { $autoDisabled = $false }
    }
    if ($autoUpdate -and -not $autoDisabled) {
        $failed += "update.auto: expected false, got $autoUpdate"
    }

    $tgAllow = Get-OCConfigValue -Key 'channels.telegram.allowFrom'
    if ($tgAllow -and $tgAllow -match '\*') {
        $failed += "telegram_allowFrom contains wildcard *"
    }

    if (-not (Test-PortListening -Port $script:OC_PORT)) {
        $failed += "port $($script:OC_PORT) not listening"
    }

    $updateTaskState = Get-TaskState -TaskName $script:OC_UPDATE_TASK
    if ($updateTaskState -ne 'Disabled') {
        $failed += "OpenClaw Update task state=$updateTaskState (expected Disabled)"
    }

    return $failed
}

# ============================================================
#  Update: -Update -Json (R7 state machine)
# ============================================================
function Invoke-Update {
    $status = Invoke-StatusInternal

    $relation = $status.relation
    $previousVersion = $status.current_version
    $targetVersion = $status.target_version
    $health = $status.health
    $channel = $status.channel

    $receipt = [ordered]@{
        schema           = 'managed_component_update_receipt.v1'
        component_id     = $componentId
        overall          = 'failed'
        changed          = $false
        previous_version = $previousVersion
        target_version   = $targetVersion
        installed_version = $null
        channel          = $channel
        phases           = [ordered]@{
            backup    = 'skipped'
            preflight = 'skipped'
            update    = 'skipped'
            wait      = 'skipped'
            verify    = 'skipped'
        }
        failed_checks    = @()
        rollback_reference = $null
        notes            = @()
    }

    # R7: state machine by relation
    switch ($relation) {
        'equal' {
            $receipt.installed_version = $previousVersion
            $verifyFailed = @(Invoke-Verify -ExpectedVersion $targetVersion -InstalledVersion $previousVersion)
            if ($health -ne 'healthy') {
                $receipt.failed_checks += "health_degraded: $health (no reinstall — update is not repair)"
                $receipt.notes += "health=$health but no update performed (equal version)"
            }
            $receipt.failed_checks += $verifyFailed
            if ($health -eq 'healthy' -and $verifyFailed.Count -eq 0) {
                $receipt.overall = 'succeeded'
                $receipt.phases.verify = 'passed'
            } else {
                $receipt.overall = 'failed'
                $receipt.phases.verify = 'failed'
            }
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            if ($receipt.overall -eq 'succeeded') { exit 0 } else { exit 1 }
        }
        'ahead' {
            $receipt.installed_version = $previousVersion
            $receipt.notes += 'ahead_of_target: current newer than registry target, no downgrade'
            $verifyFailed = @(Invoke-Verify -ExpectedVersion $previousVersion -InstalledVersion $previousVersion)
            if ($health -ne 'healthy') {
                $receipt.failed_checks += "health_degraded: $health (no reinstall — update is not repair)"
                $receipt.notes += "health=$health but no update performed (ahead version)"
            }
            $receipt.failed_checks += $verifyFailed
            if ($health -eq 'healthy' -and $verifyFailed.Count -eq 0) {
                $receipt.overall = 'succeeded'
                $receipt.phases.verify = 'passed'
            } else {
                $receipt.overall = 'failed'
                $receipt.phases.verify = 'failed'
            }
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            if ($receipt.overall -eq 'succeeded') { exit 0 } else { exit 1 }
        }
        'unknown' {
            $receipt.overall = 'failed'
            $receipt.failed_checks += 'relation_unknown: cannot determine target version, no update'
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 1
        }
        'channel_mismatch' {
            $receipt.overall = 'failed'
            $receipt.failed_checks += 'channel_mismatch: channel config unreadable or inconsistent, no update'
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 1
        }
        'behind' {
            # proceed to backup -> preflight -> update -> wait -> verify
        }
        default {
            $receipt.overall = 'failed'
            $receipt.failed_checks += "unexpected_relation: $relation"
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 1
        }
    }

    # --- behind: backup phase ---
    $backupResult = Invoke-Backup -BackupScriptPath $BackupScript
    if (-not $backupResult.ok) {
        $receipt.phases.backup = 'failed'
        $receipt.overall = 'failed'
        $receipt.failed_checks += "backup_failed: $($backupResult.error)"
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 1
    }
    $receipt.phases.backup = 'passed'
    $receipt.rollback_reference = $backupResult.backup_path

    # --- behind: preflight phase ---
    $receipt.phases.preflight = 'passed'
    $preflightFailed = @()

    $taskState = Get-TaskState -TaskName $script:OC_TASK
    if (-not $taskState) {
        $preflightFailed += "task_not_found: $script:OC_TASK"
    }

    try {
        $null = Get-Command openclaw -ErrorAction Stop
    } catch {
        $preflightFailed += 'openclaw_not_found'
    }

    if ($preflightFailed.Count -gt 0) {
        $receipt.phases.preflight = 'failed'
        $receipt.overall = 'failed'
        $receipt.failed_checks += $preflightFailed
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 1
    }

    # --- behind: official update while the Gateway is stopped ---
    $installCompleted = $false
    $preRestartPids = @(Get-PortOwningProcessIds -Port $script:OC_PORT)
    try {
        Stop-Gateway
        $updateArguments = if ($channel -eq 'extended-stable') {
            @(
                'update', '--channel', 'extended-stable', '--yes', '--json',
                '--no-restart', '--timeout', '1800'
            )
        } else {
            @(
                'update', '--tag', $targetVersion, '--yes', '--json',
                '--no-restart', '--timeout', '1800'
            )
        }
        $updateRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList $updateArguments -TimeoutSec 10800
        if ($updateRun.TimedOut -or $updateRun.ExitCode -ne 0) {
            throw 'official update command failed'
        }
        try { $updateResult = $updateRun.Stdout | ConvertFrom-Json -Depth 50 }
        catch { throw 'official update returned invalid JSON' }
        $plugins = $updateResult.postUpdate.plugins
        $pluginFailures = @($plugins.sync.errors).Count +
            @($plugins.integrityDrifts).Count +
            @($plugins.npm.outcomes | Where-Object { $_.status -eq 'error' }).Count
        if ([string]$updateResult.status -cne 'ok' -or
            [string]$updateResult.after.version -cne $targetVersion -or
            [string]$plugins.status -eq 'error' -or $pluginFailures -gt 0) {
            throw 'official update verification failed'
        }
        $installCompleted = $true
        $receipt.changed = $true
        $installedVersion = $targetVersion
        $receipt.installed_version = $installedVersion
        $receipt.changed = ($installedVersion -ne $previousVersion)
        $receipt.phases.update = 'passed'
    }
    catch {
        $receipt.phases.update = 'failed'
        $currentRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('--version') -TimeoutSec 30
        $currentVersion = Get-OpenClawVersionToken -Text $currentRun.Stdout
        $changedOnFailure = $currentVersion -and $currentVersion -cne $previousVersion
        $receipt.notes += 'Automatic version/config downgrade is disabled; use openclaw update repair for the installed generation.'
        try { Start-Gateway }
        catch { $receipt.failed_checks += 'restart_after_failed_update_failed' }
        $receipt.overall = if ($changedOnFailure) { 'partial' } else { 'failed' }
        $receipt.changed = [bool]$changedOnFailure
        $receipt.failed_checks += 'official_update_failed'
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        if ($changedOnFailure) { exit 2 } else { exit 1 }
    }

    # --- behind: start the updated Gateway ---
    $restartFailed = $false
    try {
        Start-Gateway
    } catch {
        $restartFailed = $true
        $receipt.failed_checks += 'start_failed'
    }

    # --- behind: wait phase ---
    $healthy = Wait-GatewayHealthy -Port $script:OC_PORT -MaxWaitSec $script:OC_WAIT_MAX_SEC -StableSec $script:OC_WAIT_STABLE_SEC -PreviousOwningProcessIds $preRestartPids
    if ($healthy -and -not $restartFailed) {
        $receipt.phases.wait = 'passed'
    } else {
        $receipt.phases.wait = 'failed'
        $receipt.failed_checks += "listener_not_restarted: port $($script:OC_PORT) did not transition to a new stable listener within $($script:OC_WAIT_MAX_SEC)s"
    }

    # --- behind: verify phase ---
    $verifyFailed = @(Invoke-Verify -ExpectedVersion $targetVersion -InstalledVersion $receipt.installed_version)
    if ($verifyFailed.Count -eq 0 -and $receipt.phases.wait -eq 'passed') {
        $receipt.phases.verify = 'passed'
        $receipt.overall = 'succeeded'
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 0
    } else {
        $receipt.phases.verify = 'failed'
        $receipt.failed_checks += $verifyFailed
        if ($receipt.changed) {
            $receipt.overall = 'partial'
        } else {
            $receipt.overall = 'failed'
        }
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 2
    }
}

# Internal status probe (used by Update without emitting to stdout)
function Invoke-StatusInternal {
    $channel = 'stable'
    $channelResolveOk = $true
    try {
        $chRaw = Get-OCConfigValue -Key 'update.channel'
        if ($chRaw) {
            $chTrim = $chRaw.Trim().ToLowerInvariant()
            if ($chTrim -in @('stable', 'beta', 'dev', 'extended-stable')) {
                $channel = $chTrim
            } elseif ($chTrim) {
                $channelResolveOk = $false
                $channel = 'unknown'
            }
        }
    } catch {
        $channelResolveOk = $false
        $channel = 'unknown'
    }

    $tag = ConvertTo-NpmTag -Channel $channel

    $currentVersion = $null
    $currentProbeOk = $false
    try {
        $verRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('--version') -TimeoutSec 30
        $currentProbeOk = ($verRun.ExitCode -eq 0)
        $currentVersion = Get-OpenClawVersionToken -Text $verRun.Stdout
    } catch { $currentProbeOk = $false }

    $targetVersion = $null
    $targetProbeOk = $false
    try {
        $targetVersion = Get-OcOfficialTargetVersion
        $targetProbeOk = -not [string]::IsNullOrWhiteSpace($targetVersion)
    } catch { $targetProbeOk = $false }

    $health = 'unknown'
    try {
        if (Test-OcGatewayHealth) { $health = 'healthy' } else { $health = 'degraded' }
    } catch { $health = 'unknown' }

    $relation = Get-VersionRelation `
        -CurrentVersion $currentVersion `
        -TargetVersion $targetVersion `
        -CurrentProbeOk $currentProbeOk `
        -TargetProbeOk $targetProbeOk `
        -Channel $channel `
        -ChannelResolveOk $channelResolveOk

    return [ordered]@{
        current_version  = $currentVersion
        target_version   = $targetVersion
        channel          = $channel
        relation         = $relation
        current_probe_ok = $currentProbeOk
        target_probe_ok  = $targetProbeOk
        health           = $health
    }
}

# ============================================================
#  Main dispatch
# ============================================================
if ($env:OPENCLAW_MANAGED_TESTING -eq '1') {
    $testHooksPath = $env:OPENCLAW_MANAGED_TEST_HOOKS
    if ([string]::IsNullOrWhiteSpace($testHooksPath) -or -not (Test-Path -LiteralPath $testHooksPath)) {
        [Console]::Error.WriteLine('OPENCLAW_MANAGED_TESTING requires OPENCLAW_MANAGED_TEST_HOOKS')
        exit 3
    }
    . $testHooksPath
}

if ($Status) {
    Invoke-Status
}
if ($Update) {
    Invoke-Update
}
