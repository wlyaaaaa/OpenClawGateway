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
function Invoke-ExternalLines {
    param([string]$FilePath, [string[]]$ArgumentList, [int]$TimeoutSec)
    if ($ArgumentList.Count -ge 3 -and
        $ArgumentList[0] -eq 'update' -and
        $ArgumentList[1] -eq 'status' -and
        $ArgumentList -contains '--json') {
        $exitCodeProperty = $scenario.PSObject.Properties['update_status_exit']
        $code = if ($null -ne $exitCodeProperty) { [int]$exitCodeProperty.Value } else { 0 }
        $rawStatusProperty = $scenario.PSObject.Properties['update_status_raw']
        $stdout = if ($code -eq 0) {
            if ($null -ne $rawStatusProperty) {
                [string]$rawStatusProperty.Value
            } else {
                [ordered]@{
                    availability = [ordered]@{ latestVersion = [string]$scenario.update_status_target }
                } | ConvertTo-Json -Depth 8
            }
        } else {
            ''
        }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList.Count -gt 0 -and $ArgumentList[0] -eq 'update' -and $ArgumentList -contains '--yes') {
        Add-TestTrace 'official_update'
        Add-TestTrace ('official_update_args=' + ($ArgumentList -join '|'))
        $code = [int]$scenario.npm_exit
        $stdout = if ($code -eq 0) {
            [ordered]@{
                status='ok'
                after=[ordered]@{ version=[string]$scenario.installed_version }
                postUpdate=[ordered]@{
                    plugins=[ordered]@{
                        status='ok'
                        sync=[ordered]@{ errors=@() }
                        integrityDrifts=@()
                        npm=[ordered]@{ outcomes=@() }
                    }
                }
            } | ConvertTo-Json -Depth 8
        } else { '' }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList -contains '--version') {
        $code = [int]$scenario.version_probe_exit
        $stdout = if ($code -eq 0) { [string]$scenario.installed_version } else { '' }
        $stderr = if ($code -eq 0) { '' } else { "injected failure mentioning $($scenario.installed_version)" }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=($stdout + $stderr); Stdout=$stdout; Stderr=$stderr; TimedOut=$false }
    }
    if ($ArgumentList[0] -eq 'config' -and $ArgumentList[1] -eq 'validate') {
        $stdout = @{ valid=[bool]$scenario.config_valid } | ConvertTo-Json -Compress
        return [pscustomobject]@{ ExitCode=$(if($scenario.config_valid){0}else{1}); Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList[0] -eq 'gateway' -and $ArgumentList[1] -eq 'status') {
        $stdout = @{ rpc=@{ ok=[bool]$scenario.rpc_ok } } | ConvertTo-Json -Compress
        return [pscustomobject]@{ ExitCode=$(if($scenario.rpc_ok){0}else{1}); Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList.Count -eq 3 -and
        $ArgumentList[0] -eq 'models' -and
        $ArgumentList[1] -eq 'status' -and
        $ArgumentList[2] -eq '--json') {
        Add-TestTrace 'models_status'
        $code = [int]$scenario.models_status_exit
        $stdout = if ($code -ne 0) {
            ''
        } elseif ([bool]$scenario.models_status_malformed) {
            '{"unterminated":'
        } else {
            $scenario.models_status | ConvertTo-Json -Depth 12 -Compress
        }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList.Count -eq 3 -and
        $ArgumentList[0] -eq 'models' -and
        $ArgumentList[1] -eq 'list' -and
        $ArgumentList[2] -eq '--json') {
        Add-TestTrace 'models_list'
        $code = [int]$scenario.models_directory_exit
        $stdout = if ($code -ne 0) {
            ''
        } elseif ([bool]$scenario.models_directory_malformed) {
            '{"unterminated":'
        } else {
            $scenario.models_directory | ConvertTo-Json -Depth 12 -Compress
        }
        return [pscustomobject]@{ ExitCode=$code; Lines=@($stdout); Text=$stdout; Stdout=$stdout; Stderr=''; TimedOut=$false }
    }
    if ($ArgumentList.Count -gt 0 -and $ArgumentList[0] -eq 'models') {
        throw "unexpected models command: $($ArgumentList -join ' ')"
    }
    return [pscustomobject]@{ ExitCode=0; Lines=@('ok'); Text='ok'; Stdout='ok'; Stderr=''; TimedOut=$false }
}
function Get-TaskState {
    param([string]$TaskName)
    if ($TaskName -eq 'OpenClaw Update') { return [string]$scenario.update_task_state }
    return 'Running'
}
function Get-ScheduledTask { param([string]$TaskName) return [pscustomobject]@{ TaskName=$TaskName; State='Running' } }
function Stop-Gateway { Add-TestTrace 'stop' }
function Start-Gateway {
    Add-TestTrace 'start'
    if (-not $scenario.wait_healthy -or -not $scenario.listener_changed) {
        throw 'injected start failure'
    }
}
function Test-OcGatewayHealth { return [bool]$scenario.port_listening }
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
        'update.channel' {
            $channelProperty = $scenario.PSObject.Properties['update_channel']
            if ($null -eq $channelProperty) { return $null }
            return [string]$channelProperty.Value
        }
        'update.checkOnStart' { return [string]$scenario.check_on_start }
        'update.auto' { return '{"enabled":false}' }
        'channels.telegram.allowFrom' { return [string]$scenario.telegram_allow }
        default { return $null }
    }
}
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
            [bool]$ConfigValid = $true,
            [bool]$RpcOk = $true,
            [string]$Channel = 'stable',
            [string]$DefaultModel = 'custom/local-model',
            [string[]]$AllowedRoutes = @('custom/local-model'),
            [object[]]$AuthProviders = @(),
            [object[]]$ModelDirectoryEntries,
            [int]$ModelsStatusExit = 0,
            [bool]$ModelsStatusMalformed = $false,
            [int]$ModelsDirectoryExit = 0,
            [bool]$ModelsDirectoryMalformed = $false,
            [string]$CheckOnStart = 'false',
            [string]$TelegramAllow = 'user1,user2',
            [string]$UpdateTaskState = 'Disabled'
        )
        $target = if ($Relation -in @('unknown','channel_mismatch')) { $null } elseif ($Relation -eq 'ahead') { '2026.7.0' } elseif ($Relation -eq 'equal') { '2026.7.1' } else { '2026.7.2' }
        $effectiveDirectoryEntries = if ($null -eq $ModelDirectoryEntries) {
            @([ordered]@{ key=$DefaultModel; local=$true })
        } else {
            @($ModelDirectoryEntries)
        }
        $scenario = [ordered]@{
            status = [ordered]@{ current_version='2026.7.1'; target_version=$target; channel=$Channel; relation=$Relation; current_probe_ok=$true; target_probe_ok=($null -ne $target); health=$Health }
            backup_ok=$BackupOk; is_admin=$IsAdmin; npm_exit=$NpmExit; installed_version=$InstalledVersion; version_probe_exit=$VersionProbeExit
            update_channel=$Channel; update_status_exit=0; update_status_target=$target
            wait_healthy=$WaitHealthy; require_listener_transition=$RequireListenerTransition; listener_changed=$ListenerChanged; port_listening=$PortListening
            config_valid=$ConfigValid; rpc_ok=$RpcOk
            models_status_exit=$ModelsStatusExit; models_status_malformed=$ModelsStatusMalformed
            models_status=[ordered]@{
                defaultModel=$DefaultModel
                allowed=@($AllowedRoutes)
                auth=[ordered]@{ providers=@($AuthProviders) }
            }
            models_directory_exit=$ModelsDirectoryExit; models_directory_malformed=$ModelsDirectoryMalformed
            models_directory=[ordered]@{ models=@($effectiveDirectoryEntries) }
            check_on_start=$CheckOnStart; telegram_allow=$TelegramAllow; update_task_state=$UpdateTaskState
        }
        $scenario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ScenarioPath -Encoding utf8
        Remove-Item -LiteralPath $script:TracePath -Force -ErrorAction SilentlyContinue
        $env:OPENCLAW_MANAGED_TEST_SCENARIO = $script:ScenarioPath
        $env:OPENCLAW_MANAGED_TEST_TRACE = $script:TracePath
        $env:OPENCLAW_MANAGED_TESTING = '1'
        $env:OPENCLAW_MANAGED_TEST_HOOKS = $script:HookPath
        $output = pwsh -NoProfile -File $script:Adapter -Update -Json 2>$null
        $exitCode = $LASTEXITCODE
        $trace = if (Test-Path $script:TracePath) { @(Get-Content -LiteralPath $script:TracePath) } else { @() }
        return [pscustomobject]@{ Receipt=($output | ConvertFrom-Json); ExitCode=$exitCode; Trace=$trace }
    }

    function Invoke-ProductionStatusScenario {
        param(
            [string]$Channel,
            [string]$CurrentVersion = '2026.7.1',
            [string]$TargetVersion = '2026.7.1'
        )
        $scenario = [ordered]@{
            update_channel=$Channel; update_status_exit=0; update_status_target=$TargetVersion
            installed_version=$CurrentVersion; version_probe_exit=0; port_listening=$true
        }
        $scenario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ScenarioPath -Encoding utf8
        Remove-Item -LiteralPath $script:TracePath -Force -ErrorAction SilentlyContinue
        $env:OPENCLAW_MANAGED_TEST_SCENARIO = $script:ScenarioPath
        $env:OPENCLAW_MANAGED_TEST_TRACE = $script:TracePath
        $env:OPENCLAW_MANAGED_TESTING = '1'
        $env:OPENCLAW_MANAGED_TEST_HOOKS = $script:HookPath
        $output = pwsh -NoProfile -File $script:Adapter -Status -Json 2>$null
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{ Status=($output | ConvertFrom-Json); ExitCode=$exitCode }
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
        @{ status=@{}; installed_version='2026.7.1'; version_probe_exit=0; update_channel='stable'; update_status_exit=0; update_status_raw='ok'; update_task_state='Disabled'; wait_healthy=$true; port_listening=$true; api_mode='openai-completions'; check_on_start='false'; telegram_allow='user1' } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ScenarioPath -Encoding utf8
        $output = pwsh -NoProfile -File $script:Adapter -Status -Json 2>$null
        $status = $output | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $status.target_version | Should -BeNullOrEmpty
        $status.relation | Should -Be 'unknown'
    }

    It 'accepts extended-stable status without a channel mismatch' {
        $r = Invoke-ProductionStatusScenario -Channel 'extended-stable'
        $r.ExitCode | Should -Be 0
        $r.Status.channel | Should -Be 'extended-stable'
        $r.Status.relation | Should -Be 'equal'
    }

    It 'equal healthy accepts a custom local=true default without remote auth' {
        $r = Invoke-ProductionScenario -Relation equal
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.changed | Should -BeFalse
        $r.Trace | Should -Not -Contain 'backup'
        $r.Trace | Should -Not -Contain 'official_update'
        @($r.Trace | Where-Object { $_ -eq 'models_status' }).Count | Should -Be 1
        @($r.Trace | Where-Object { $_ -eq 'models_list' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 0
    }

    It 'requires auth for ollama-cloud when its exact directory entry is not local' {
        $r = Invoke-ProductionScenario -Relation equal -DefaultModel 'ollama-cloud/model-a' -AllowedRoutes @('ollama-cloud/model-a') -ModelDirectoryEntries @([pscustomobject]@{ key='ollama-cloud/model-a'; local=$false })
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'default_provider_auth_missing: ollama-cloud'
        @($r.Trace | Where-Object { $_ -eq 'models_status' }).Count | Should -Be 1
        @($r.Trace | Where-Object { $_ -eq 'models_list' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 1
    }

    It 'accepts a remote default with a usable auth source' {
        $authProvider = [pscustomobject]@{
            provider = 'acme'
            profiles = [pscustomobject]@{ count = 0 }
            effective = [pscustomobject]@{ kind = 'env' }
        }
        $r = Invoke-ProductionScenario -Relation equal -DefaultModel 'acme/model-a' -AllowedRoutes @('acme/model-a') -AuthProviders @($authProvider) -ModelDirectoryEntries @([pscustomobject]@{ key='acme/model-a'; local=$false })
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.ExitCode | Should -Be 0
    }

    It 'treats a missing default directory entry as remote and requires auth' {
        $r = Invoke-ProductionScenario -Relation equal -DefaultModel 'acme/model-a' -AllowedRoutes @('acme/model-a') -ModelDirectoryEntries @()
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'default_provider_auth_missing: acme'
        $r.ExitCode | Should -Be 1
    }

    It 'treats an entry without local=true as remote and requires auth' {
        $r = Invoke-ProductionScenario -Relation equal -DefaultModel 'acme/model-a' -AllowedRoutes @('acme/model-a') -ModelDirectoryEntries @([pscustomobject]@{ key='acme/model-a' })
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'default_provider_auth_missing: acme'
        $r.ExitCode | Should -Be 1
    }

    It 'rejects a failed models status command' {
        $r = Invoke-ProductionScenario -Relation equal -ModelsStatusExit 1
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'models_status_unavailable'
        @($r.Trace | Where-Object { $_ -eq 'models_status' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 1
    }

    It 'rejects malformed models status JSON' {
        $r = Invoke-ProductionScenario -Relation equal -ModelsStatusMalformed $true
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'models_status_unavailable'
        @($r.Trace | Where-Object { $_ -eq 'models_status' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 1
    }

    It 'rejects a failed models directory command' {
        $r = Invoke-ProductionScenario -Relation equal -ModelsDirectoryExit 1
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'models_directory_unavailable'
        @($r.Trace | Where-Object { $_ -eq 'models_list' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 1
    }

    It 'rejects malformed models directory JSON' {
        $r = Invoke-ProductionScenario -Relation equal -ModelsDirectoryMalformed $true
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'models_directory_unavailable'
        @($r.Trace | Where-Object { $_ -eq 'models_list' }).Count | Should -Be 1
        $r.ExitCode | Should -Be 1
    }

    It 'requires the default model route to be allowed' {
        $authProvider = [pscustomobject]@{
            provider = 'acme'
            profiles = [pscustomobject]@{ count = 0 }
            effective = [pscustomobject]@{ kind = 'env' }
        }
        $r = Invoke-ProductionScenario -Relation equal -DefaultModel 'acme/model-a' -AllowedRoutes @('acme/model-b') -AuthProviders @($authProvider) -ModelDirectoryEntries @([pscustomobject]@{ key='acme/model-a'; local=$false })
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'model_default_route_missing: acme/model-a'
        ($r.Receipt.failed_checks -join ' ') | Should -Not -Match 'default_provider_auth_missing'
        $r.ExitCode | Should -Be 1
    }

    It 'equal degraded reports health without reinstalling' {
        $r = Invoke-ProductionScenario -Relation equal -Health degraded
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'health_degraded'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Be 1
    }

    It 'unknown and channel_mismatch never start a transaction' -ForEach @('unknown','channel_mismatch') {
        $r = Invoke-ProductionScenario -Relation $_
        $r.Receipt.overall | Should -Be 'failed'
        $r.Trace | Should -Not -Contain 'backup'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Not -Be 0
    }

    It 'ahead never downgrades' {
        $r = Invoke-ProductionScenario -Relation ahead
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.phases.verify | Should -Be 'passed'
        @($r.Receipt.failed_checks).Count | Should -Be 0
        ($r.Receipt.notes -join ' ') | Should -Match 'ahead_of_target'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Be 0
    }

    It 'ahead degraded fails verification without downgrading' {
        $r = Invoke-ProductionScenario -Relation ahead -Health degraded
        $r.Receipt.overall | Should -Be 'failed'
        $r.Receipt.phases.verify | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'health_degraded'
        ($r.Receipt.failed_checks -join ' ') | Should -Not -Match 'ahead_of_target'
        ($r.Receipt.notes -join ' ') | Should -Match 'ahead_of_target'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Be 1
    }

    It 'ahead post-verification failure cannot report success or downgrade' {
        $r = Invoke-ProductionScenario -Relation ahead -CheckOnStart 'true'
        $r.Receipt.overall | Should -Be 'failed'
        $r.Receipt.phases.verify | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'checkOnStart'
        ($r.Receipt.failed_checks -join ' ') | Should -Not -Match 'ahead_of_target'
        ($r.Receipt.notes -join ' ') | Should -Match 'ahead_of_target'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Be 1
    }

    It 'backup failure prevents the official update' {
        $r = Invoke-ProductionScenario -Relation behind -BackupOk $false
        $r.Receipt.phases.backup | Should -Be 'failed'
        $r.Trace | Should -Contain 'backup'
        $r.Trace | Should -Not -Contain 'official_update'
        $r.ExitCode | Should -Not -Be 0
    }

    It 'successful behind path executes the real production branch' {
        $r = Invoke-ProductionScenario -Relation behind -RequireListenerTransition $true
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.installed_version | Should -Be '2026.7.2'
        $r.Receipt.phases.backup | Should -Be 'passed'
        $r.Receipt.phases.verify | Should -Be 'passed'
        $r.Trace | Should -Contain 'stop'
        $r.Trace | Should -Contain 'official_update'
        @($r.Trace | Where-Object { $_ -like 'official_update_args=*' }) | Should -Be @('official_update_args=update|--tag|2026.7.2|--yes|--json|--no-restart|--timeout|1800')
        $r.Trace | Should -Contain 'start'
        $r.ExitCode | Should -Be 0
    }

    It 'uses extended-stable channel update without a target tag' {
        $r = Invoke-ProductionScenario -Relation behind -Channel 'extended-stable' -RequireListenerTransition $true
        $r.Receipt.overall | Should -Be 'succeeded'
        $r.Receipt.channel | Should -Be 'extended-stable'
        $updateArguments = @($r.Trace | Where-Object { $_ -like 'official_update_args=*' })
        $updateArguments | Should -Be @('official_update_args=update|--channel|extended-stable|--yes|--json|--no-restart|--timeout|1800')
        $updateArguments | Should -Not -Match '--tag'
        $r.ExitCode | Should -Be 0
    }

    It 'does not accept an unchanged old listener as restart success' {
        $r = Invoke-ProductionScenario -Relation behind -RequireListenerTransition $true -ListenerChanged $false
        $r.Receipt.phases.wait | Should -Be 'failed'
        $r.Receipt.overall | Should -Be 'partial'
        $r.ExitCode | Should -Be 2
    }

    It 'does not report success when the official update fails before changing version' {
        $r = Invoke-ProductionScenario -Relation behind -NpmExit 1 -InstalledVersion '2026.7.1'
        $r.Receipt.overall | Should -Be 'failed'
        $r.Receipt.changed | Should -BeFalse
        $r.Receipt.phases.update | Should -Be 'failed'
        $r.ExitCode | Should -Be 1
    }

    It 'does not downgrade or restore old config after a partial official update' {
        $r = Invoke-ProductionScenario -Relation behind -NpmExit 1 -InstalledVersion '2026.8.1'
        $r.Receipt.overall | Should -Be 'partial'
        @($r.Trace | Where-Object { $_ -eq 'official_update' }).Count | Should -Be 1
        $r.Trace | Should -Contain 'start'
        ($r.Receipt.notes -join ' ') | Should -Match 'update repair'
        $r.ExitCode | Should -Be 2
    }

    It 'requires schema, RPC, default model, and allowed routes at equal version' {
        $r = Invoke-ProductionScenario -Relation equal -ConfigValid $false -RpcOk $false -DefaultModel '' -AllowedRoutes @()
        $r.Receipt.overall | Should -Be 'failed'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'config_schema_invalid'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'gateway_rpc_unavailable'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'model_default_missing'
        ($r.Receipt.failed_checks -join ' ') | Should -Match 'model_allowed_routes_missing'
        $r.ExitCode | Should -Be 1
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
