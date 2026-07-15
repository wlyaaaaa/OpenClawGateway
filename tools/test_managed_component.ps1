#Requires -Version 7.0
<#
  Pester 6 end-to-end state-machine tests for the real managed-component.ps1.
  The production script is executed in a child pwsh process with test hooks that
  replace only external effects. This prevents a duplicate test-only state machine.
#>
[CmdletBinding()]
param()

BeforeAll {
    $script:Adapter = Join-Path $PSScriptRoot 'managed-component.ps1'
    $script:TempRoot = Join-Path $env:TEMP "openclaw-managed-component-production-tests-$PID"
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    $script:ScenarioPath = Join-Path $script:TempRoot 'scenario.json'
    $script:TracePath = Join-Path $script:TempRoot 'trace.txt'
    $script:HookPath = Join-Path $script:TempRoot 'hooks.ps1'
    $script:RestartOk = Join-Path $script:TempRoot 'restart-ok.ps1'
    "exit 0" | Set-Content -LiteralPath $script:RestartOk -Encoding utf8

    @'
$scenario = Get-Content -LiteralPath $env:OPENCLAW_MANAGED_TEST_SCENARIO -Raw | ConvertFrom-Json
$tracePath = $env:OPENCLAW_MANAGED_TEST_TRACE
function Add-TestTrace([string]$Value) { Add-Content -LiteralPath $tracePath -Value $Value -Encoding utf8 }
function Invoke-StatusInternal { return $scenario.status }
function Invoke-Backup {
    param([string]$BackupScriptPath)
    Add-TestTrace 'backup'
    return [ordered]@{ ok=[bool]$scenario.backup_ok; backup_path='E:\fake-backup'; error=$(if($scenario.backup_ok){$null}else{'injected backup failure'}) }
}
function Test-IsAdmin { return [bool]$scenario.is_admin }
function Resolve-NpmCmd { return 'C:\fake\npm.cmd' }
function Invoke-ExternalLines {
    param([string]$FilePath, [string[]]$ArgumentList, [int]$TimeoutSec)
    if ($ArgumentList -contains 'install') {
        Add-TestTrace 'npm_install'
        return [pscustomobject]@{ ExitCode=[int]$scenario.npm_exit; Lines=@('npm'); Text='npm'; Stdout='npm'; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList -contains '--version') {
        $code = [int]$scenario.version_probe_exit
        $stdout = if ($code -eq 0) { [string]$scenario.installed_version } else { '' }
        $stderr = if ($code -eq 0) { '' } else { "injected failure mentioning $($scenario.installed_version)" }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=($stdout + $stderr); Stdout=$stdout; Stderr=$stderr; TimedOut=$false }
    }
    return [pscustomobject]@{ ExitCode=0; Lines=@('ok'); Text='ok'; Stdout='ok'; Stderr=''; TimedOut=$false }
}
function Get-TaskState {
    param([string]$TaskName)
    if ($TaskName -eq 'OpenClaw Update') { return [string]$scenario.update_task_state }
    return 'Running'
}
function Get-ScheduledTask { param([string]$TaskName) return [pscustomobject]@{ TaskName=$TaskName; State='Running' } }
function Get-PortOwningProcessIds { param([int]$Port) return @(111) }
function Wait-GatewayHealthy {
    param([int]$Port,[int]$MaxWaitSec,[int]$StableSec,[int[]]$PreviousOwningProcessIds=@())
    if ($scenario.require_listener_transition) {
        return [bool]($scenario.wait_healthy -and $scenario.listener_changed -and ($PreviousOwningProcessIds -contains 111))
    }
    return [bool]$scenario.wait_healthy
}
function Test-PortListening { param([int]$Port) return [bool]$scenario.port_listening }
function Get-OCConfigValue {
    param([string]$Key)
    switch ($Key) {
        'models.providers.openai.api' { return [string]$scenario.api_mode }
        'update.checkOnStart' { return [string]$scenario.check_on_start }
        'channels.telegram.allowFrom' { return [string]$scenario.telegram_allow }
        default { return $null }
    }
}
function Set-OCConfigValue { param([string]$Key,[string]$Value) }
'@ | Set-Content -LiteralPath $script:HookPath -Encoding utf8

    function Invoke-ProductionScenario {
        param(
            [string]$Relation,
            [string]$Health = 'healthy',
            [bool]$BackupOk = $true,
            [bool]$IsAdmin = $true,
            [int]$NpmExit = 0,
            [int]$VersionProbeExit = 0,
            [string]$InstalledVersion = '2026.7.2',
            [bool]$WaitHealthy = $true,
            [bool]$RequireListenerTransition = $false,
            [bool]$ListenerChanged = $true,
            [bool]$PortListening = $true,
            [string]$ApiMode = 'openai-completions',
            [string]$CheckOnStart = 'false',
            [string]$TelegramAllow = 'user1,user2',
            [string]$UpdateTaskState = 'Disabled'
        )
        $target = if ($Relation -in @('unknown','channel_mismatch')) { $null } elseif ($Relation -eq 'ahead') { '2026.7.0' } elseif ($Relation -eq 'equal') { '2026.7.1' } else { '2026.7.2' }
        $scenario = [ordered]@{
            status = [ordered]@{ current_version='2026.7.1'; target_version=$target; channel='stable'; relation=$Relation; current_probe_ok=$true; target_probe_ok=($null -ne $target); health=$Health }
            backup_ok=$BackupOk; is_admin=$IsAdmin; npm_exit=$NpmExit; installed_version=$InstalledVersion; version_probe_exit=$VersionProbeExit
            wait_healthy=$WaitHealthy; require_listener_transition=$RequireListenerTransition; listener_changed=$ListenerChanged; port_listening=$PortListening; api_mode=$ApiMode
            check_on_start=$CheckOnStart; telegram_allow=$TelegramAllow; update_task_state=$UpdateTaskState
        }
        $scenario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ScenarioPath -Encoding utf8
        Remove-Item -LiteralPath $script:TracePath -Force -ErrorAction SilentlyContinue
        $env:OPENCLAW_MANAGED_TEST_SCENARIO = $script:ScenarioPath
        $env:OPENCLAW_MANAGED_TEST_TRACE = $script:TracePath
        $env:OPENCLAW_MANAGED_TESTING = '1'
        $env:OPENCLAW_MANAGED_TEST_HOOKS = $script:HookPath
        $output = pwsh -NoProfile -File $script:Adapter -Update -Json -RestartScript $script:RestartOk 2>$null
        $exitCode = $LASTEXITCODE
        $trace = if (Test-Path $script:TracePath) { @(Get-Content -LiteralPath $script:TracePath) } else { @() }
        return [pscustomobject]@{ Receipt=($output | ConvertFrom-Json); ExitCode=$exitCode; Trace=$trace }
    }
}

Describe 'Production managed-component state machine' {
    It 'rejects ambiguous Status plus Update dispatch' {
        $output = pwsh -NoProfile -File $script:Adapter -Status -Update -Json 2>$null
        $LASTEXITCODE | Should -Be 3
        @($output).Count | Should -Be 0
    }

    It 'does not expose arbitrary successful command output as a target version' {
        $env:OPENCLAW_MANAGED_TEST_SCENARIO = $script:ScenarioPath
        $env:OPENCLAW_MANAGED_TEST_TRACE = $script:TracePath
        $env:OPENCLAW_MANAGED_TESTING = '1'
        $env:OPENCLAW_MANAGED_TEST_HOOKS = $script:HookPath
        @{ status=@{}; installed_version='2026.7.1'; version_probe_exit=0; update_task_state='Disabled'; wait_healthy=$true; port_listening=$true; api_mode='openai-completions'; check_on_start='false'; telegram_allow='user1' } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ScenarioPath -Encoding utf8
        $output = pwsh -NoProfile -File $script:Adapter -Status -Json 2>$null
        $status = $output | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $status.target_version | Should -BeNullOrEmpty
        $status.relation | Should -Be 'unknown'
    }

    It 'equal healthy short-circuits without backup or install' {
        $r = Invoke-ProductionScenario -Relation equal
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.changed | Should -BeFalse
        $r.Trace | Should -Not -Contain 'backup'
        $r.Trace | Should -Not -Contain 'npm_install'
        $r.ExitCode | Should -Be 0
    }

    It 'equal degraded reports health without reinstalling' {
        $r = Invoke-ProductionScenario -Relation equal -Health degraded
        $r.Receipt.overall | Should -Be 'succeeded'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'health_degraded'
        $r.Trace | Should -Not -Contain 'npm_install'
    }

    It 'unknown and channel_mismatch never start a transaction' -ForEach @('unknown','channel_mismatch') {
        $r = Invoke-ProductionScenario -Relation $_
        $r.Receipt.overall | Should -Be 'failed'
        $r.Trace | Should -Not -Contain 'backup'
        $r.Trace | Should -Not -Contain 'npm_install'
        $r.ExitCode | Should -Not -Be 0
    }

    It 'ahead never downgrades' {
        $r = Invoke-ProductionScenario -Relation ahead
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Trace | Should -Not -Contain 'npm_install'
    }

    It 'backup failure prevents npm install' {
        $r = Invoke-ProductionScenario -Relation behind -BackupOk $false
        $r.Receipt.phases.backup | Should -Be 'failed'
        $r.Trace | Should -Contain 'backup'
        $r.Trace | Should -Not -Contain 'npm_install'
        $r.ExitCode | Should -Not -Be 0
    }

    It 'successful behind path executes the real production branch' {
        $r = Invoke-ProductionScenario -Relation behind -RequireListenerTransition $true
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.installed_version | Should -Be '2026.7.2'
        $r.Receipt.phases.backup | Should -Be 'passed'
        $r.Receipt.phases.verify | Should -Be 'passed'
        $r.Trace | Should -Contain 'npm_install'
        $r.ExitCode | Should -Be 0
    }

    It 'does not accept an unchanged old listener as restart success' {
        $r = Invoke-ProductionScenario -Relation behind -RequireListenerTransition $true -ListenerChanged $false
        $r.Receipt.phases.wait | Should -Be 'failed'
        $r.Receipt.overall | Should -Be 'partial'
        $r.ExitCode | Should -Be 2
    }

    It 'treats a post-install version probe failure as partial even if stderr mentions a version' {
        $r = Invoke-ProductionScenario -Relation behind -VersionProbeExit 1
        $r.Receipt.overall | Should -Be 'partial'
        $r.Receipt.changed | Should -BeTrue
        $r.Receipt.phases.update | Should -Be 'failed'
        $r.ExitCode | Should -Be 2
    }

    It 'restart or verification failure cannot report success' -ForEach @(
        @{ wait=$false; port=$false; check='false'; task='Disabled'; installed='2026.7.2' },
        @{ wait=$true; port=$true; check='true'; task='Disabled'; installed='2026.7.2' },
        @{ wait=$true; port=$true; check='false'; task='Ready'; installed='2026.7.2' },
        @{ wait=$true; port=$true; check='false'; task='Disabled'; installed='2026.7.1' }
    ) {
        $r = Invoke-ProductionScenario -Relation behind -WaitHealthy $_.wait -PortListening $_.port -CheckOnStart $_.check -UpdateTaskState $_.task -InstalledVersion $_.installed
        $r.Receipt.overall | Should -Not -Be 'succeeded'
        $r.ExitCode | Should -Not -Be 0
    }
}

AfterAll {
    Remove-Item Env:OPENCLAW_MANAGED_TESTING -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_MANAGED_TEST_HOOKS -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_MANAGED_TEST_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_MANAGED_TEST_TRACE -ErrorAction SilentlyContinue
    $root = [IO.Path]::GetFullPath($script:TempRoot)
    $temp = [IO.Path]::GetFullPath($env:TEMP)
    if ($root.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $root) -like 'openclaw-managed-component-production-tests-*' -and
        (Test-Path -LiteralPath $root)) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
