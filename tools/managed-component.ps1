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
    [string]$RestartScript = (Join-Path $PSScriptRoot 'restart_gateway.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

. (Join-Path $PSScriptRoot '_update_lib.ps1')

$componentId = 'openclaw'
$observedUtc = [DateTime]::UtcNow.ToString('o')

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
            if ($chTrim -in @('stable', 'beta', 'dev')) {
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
        $npmCmd = Resolve-NpmCmd
        $viewRun = Invoke-ExternalLines -FilePath $npmCmd -ArgumentList @('view', "openclaw@$tag", 'version') -TimeoutSec 60
        $targetProbeOk = ($viewRun.ExitCode -eq 0)
        $targetVersion = Get-OpenClawVersionToken -Text $viewRun.Stdout
    } catch {
        $targetProbeOk = $false
    }

    $health = 'unknown'
    try {
        $listening = Test-PortListening -Port $script:OC_PORT
        if ($listening) { $health = 'healthy' } else { $health = 'degraded' }
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

    $api = Get-OCConfigValue -Key 'models.providers.openai.api'
    if ($api -ne 'openai-completions') {
        $failed += "api_mode: expected openai-completions, got $api"
    }

    $checkOnStart = Get-OCConfigValue -Key 'update.checkOnStart'
    if ($checkOnStart -ne 'false') {
        $failed += "checkOnStart: expected false, got $checkOnStart"
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
            $receipt.overall = 'succeeded'
            $receipt.installed_version = $previousVersion
            $receipt.phases.verify = 'passed'
            if ($health -ne 'healthy') {
                $receipt.failed_checks += "health_degraded: $health (no reinstall — update is not repair)"
                $receipt.notes += "health=$health but no update performed (equal version)"
            }
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 0
        }
        'ahead' {
            $receipt.overall = 'succeeded'
            $receipt.installed_version = $previousVersion
            $receipt.phases.verify = 'passed'
            $receipt.failed_checks += 'ahead_of_target: current newer than registry target, no downgrade'
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 0
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

    if (-not (Test-IsAdmin)) {
        $receipt.phases.preflight = 'failed'
        $receipt.overall = 'failed'
        $receipt.failed_checks += 'preflight_not_admin: update requires admin but process is not elevated'
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 1
    }

    $taskState = Get-TaskState -TaskName $script:OC_TASK
    if (-not $taskState) {
        $preflightFailed += "task_not_found: $script:OC_TASK"
    }

    try {
        $null = Resolve-NpmCmd
    } catch {
        $preflightFailed += "npm_not_found"
    }

    if ($preflightFailed.Count -gt 0) {
        $receipt.phases.preflight = 'failed'
        $receipt.overall = 'failed'
        $receipt.failed_checks += $preflightFailed
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        exit 1
    }

    # --- behind: update phase (npm install) ---
    $tag = ConvertTo-NpmTag -Channel $channel
    $installCompleted = $false
    try {
        $npmCmd = Resolve-NpmCmd
        [Console]::Error.WriteLine("Installing openclaw@$tag ...")
        $npmRun = Invoke-ExternalLines -FilePath $npmCmd -ArgumentList @('install', '-g', "openclaw@$tag") -TimeoutSec 300
        [Console]::Error.WriteLine("npm exit code: $($npmRun.ExitCode)")
        if ($npmRun.ExitCode -ne 0) {
            $receipt.phases.update = 'failed'
            $receipt.overall = 'failed'
            $receipt.failed_checks += "npm_install_failed: exit $($npmRun.ExitCode)"
            Write-JsonResult -Data $receipt -ResultPath $ResultPath
            exit 1
        }
        $installCompleted = $true
        $receipt.changed = $true

        $newRun = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('--version') -TimeoutSec 30
        if ($newRun.ExitCode -ne 0 -or $newRun.TimedOut) {
            throw "post-install version probe failed (exit=$($newRun.ExitCode), timed_out=$($newRun.TimedOut))"
        }
        $installedVersion = Get-OpenClawVersionToken -Text $newRun.Stdout
        if (-not $installedVersion) {
            throw 'post-install version probe returned no valid version token'
        }
        $receipt.installed_version = $installedVersion
        $receipt.changed = ($installedVersion -ne $previousVersion)
        $receipt.phases.update = 'passed'
    }
    catch {
        $receipt.phases.update = 'failed'
        $receipt.overall = if ($installCompleted) { 'partial' } else { 'failed' }
        $receipt.failed_checks += "update_exception: $_"
        Write-JsonResult -Data $receipt -ResultPath $ResultPath
        if ($installCompleted) { exit 2 } else { exit 1 }
    }

    # --- behind: self-heal critical config ---
    $api = Get-OCConfigValue -Key 'models.providers.openai.api'
    if ($api -ne 'openai-completions') {
        Set-OCConfigValue -Key 'models.providers.openai.api' -Value 'openai-completions'
        [Console]::Error.WriteLine("Self-heal: re-asserted api=openai-completions (was: $api)")
    }

    # --- behind: restart gateway ---
    $preRestartPids = @(Get-PortOwningProcessIds -Port $script:OC_PORT)
    $restartFailed = $false
    if (Get-ScheduledTask -TaskName $script:OC_TASK -ErrorAction SilentlyContinue) {
        [Console]::Error.WriteLine("Spawning restart helper...")
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RestartScript
            if ($LASTEXITCODE -ne 0) { throw "restart helper exit code $LASTEXITCODE" }
            [Console]::Error.WriteLine("Restart helper spawned.")
        } catch {
            [Console]::Error.WriteLine("Restart helper failed: $_")
            $restartFailed = $true
            $receipt.failed_checks += "restart_failed: $_"
        }
    } else {
        $restartFailed = $true
        $receipt.failed_checks += "restart_failed: gateway task not found"
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
            if ($chTrim -in @('stable', 'beta', 'dev')) {
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
        $npmCmd = Resolve-NpmCmd
        $viewRun = Invoke-ExternalLines -FilePath $npmCmd -ArgumentList @('view', "openclaw@$tag", 'version') -TimeoutSec 60
        $targetProbeOk = ($viewRun.ExitCode -eq 0)
        $targetVersion = Get-OpenClawVersionToken -Text $viewRun.Stdout
    } catch { $targetProbeOk = $false }

    $health = 'unknown'
    try {
        $listening = Test-PortListening -Port $script:OC_PORT
        if ($listening) { $health = 'healthy' } else { $health = 'degraded' }
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
