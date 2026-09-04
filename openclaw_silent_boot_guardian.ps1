<#
.SYNOPSIS
  核对 OpenClaw Gateway 的 Windows 常驻状态；显式 -Repair 时才修复注册。
.DESCRIPTION
  现役机器优先把凭据注入和计划任务注册交给 PCConfig。没有 PCConfig 受控
  启动器时，只使用 OpenClaw 官方 gateway install，不再生成仓库内 VBS、
  写机器级密码环境变量或手工拼装 Node 计划任务。

  默认是只读检查。-Repair 会重注册网关，要求管理员权限，并在完成后通过
  Gateway RPC 和计划任务状态回读验收。
#>
[CmdletBinding()]
param(
    [string]$TaskName = 'OpenClaw Gateway',
    [int]$Port = 18789,
    [switch]$Repair,
    [switch]$Json,
    [string]$PcConfigRoot = $(
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('PCCONFIG_ROOT', 'User'))) {
            'E:\PCConfig'
        }
        else {
            [Environment]::GetEnvironmentVariable('PCCONFIG_ROOT', 'User')
        }
    ),
    [string]$ManagedLauncher = 'C:\ProgramData\PCConfig\SecretBroker\Start-OpenClawGateway.ps1',
    [string]$PwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Invoke-OpenClawJson([string[]]$Arguments) {
    $raw = & openclaw @Arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "openclaw $($Arguments -join ' ') failed."
    }
    try { return $raw | ConvertFrom-Json -Depth 30 }
    catch { throw "openclaw $($Arguments -join ' ') did not return valid JSON." }
}

function Get-TaskPosture {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return [ordered]@{
            exists = $false
            state = 'Missing'
            hidden = $false
            run_level = $null
            logon_type = $null
            boot_trigger = $false
            managed_launcher = $false
        }
    }

    $action = @($task.Actions) | Select-Object -First 1
    $triggerClasses = @($task.Triggers | ForEach-Object { $_.CimClass.CimClassName })
    return [ordered]@{
        exists = $true
        state = [string]$task.State
        hidden = $task.Settings.Hidden -eq $true
        run_level = [string]$task.Principal.RunLevel
        logon_type = [string]$task.Principal.LogonType
        boot_trigger = $triggerClasses -contains 'MSFT_TaskBootTrigger'
        managed_launcher = $null -ne $action -and
            [string]$action.Execute -ieq $PwshPath -and
            [string]$action.Arguments -match [Regex]::Escape($ManagedLauncher)
    }
}

$pcconfigInstaller = Join-Path $PcConfigRoot 'tools\Install-SecretBroker.ps1'
$pcconfigRegistry = Join-Path $PcConfigRoot 'registries\secret_broker.json'
$managedAvailable =
    (Test-Path -LiteralPath $ManagedLauncher -PathType Leaf) -and
    (Test-Path -LiteralPath $pcconfigInstaller -PathType Leaf) -and
    (Test-Path -LiteralPath $pcconfigRegistry -PathType Leaf) -and
    (Test-Path -LiteralPath $PwshPath -PathType Leaf)

$repairRoute = 'none'
if ($Repair) {
    if (-not (Test-Administrator)) {
        throw 'Repair requires an elevated Administrator PowerShell.'
    }

    if ($managedAvailable) {
        $managedRaw = & $PwshPath `
            -NoLogo `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $pcconfigInstaller `
            -RegistryPath $pcconfigRegistry `
            -SkipShortcut `
            -ConfigureOpenClawGatewayTask `
            -ScrubOpenClawGatewayEnvironment `
            -Json
        if ($LASTEXITCODE -ne 0) { throw 'PCConfig managed gateway registration failed.' }
        $managed = $managedRaw | ConvertFrom-Json -Depth 20
        if ($managed.status -ne 'pass' -or
            $managed.openclaw_gateway_task_configured -ne $true -or
            $managed.openclaw_gateway_environment_scrubbed -ne $true) {
            throw 'PCConfig managed gateway verification failed.'
        }
        $repairRoute = 'pcconfig_managed'
    }
    else {
        $null = Invoke-OpenClawJson @('gateway', 'install', '--force', '--port', [string]$Port, '--json')
        $repairRoute = 'openclaw_official'
    }
}

$gateway = Invoke-OpenClawJson @('gateway', 'status', '--require-rpc', '--json')
$rpcOk = $gateway.rpc.ok -eq $true
$taskPosture = Get-TaskPosture
$taskHealthy = $taskPosture.exists -and $taskPosture.state -ne 'Disabled'

$result = [ordered]@{
    schema = 'openclaw_gateway.windows_residency.v1'
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    repair_requested = [bool]$Repair
    repair_route = $repairRoute
    managed_route_available = [bool]$managedAvailable
    gateway_rpc_ok = [bool]$rpcOk
    gateway_version = [string]$gateway.rpc.version
    port = $Port
    task = $taskPosture
    healthy = [bool]($rpcOk -and $taskHealthy)
}

if (-not $result.healthy) {
    if ($Json) { $result | ConvertTo-Json -Depth 12 -Compress }
    throw 'OpenClaw Gateway did not pass RPC and scheduled-task readback.'
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12 -Compress
    exit 0
}

Write-Host 'OpenClaw Gateway 常驻状态' -ForegroundColor Green
Write-Host ("  RPC            {0}" -f $(if ($rpcOk) { 'ok' } else { 'failed' }))
Write-Host ("  版本           {0}" -f $result.gateway_version)
Write-Host ("  计划任务       {0}" -f $taskPosture.state)
Write-Host ("  注册路线       {0}" -f $(if ($taskPosture.managed_launcher) { 'PCConfig 受控启动器' } else { 'OpenClaw 官方任务' }))
Write-Host ("  本次修复       {0}" -f $repairRoute)
