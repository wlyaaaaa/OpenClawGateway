# =====================================================================
#  _common.ps1 — OpenClaw 工具集公共函数（被各脚本 dot-source 引用）
# =====================================================================
$script:OC   = Join-Path $env:USERPROFILE '.openclaw'
$script:TASK = 'OpenClaw Gateway'
$script:PORT = 18789
$script:AUTH = Join-Path $OC 'auth-profiles.json'

function Write-Step($m){ Write-Host "  $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "  $m" -ForegroundColor DarkGray }
function Write-Warn2($m){ Write-Host "  ! $m" -ForegroundColor Yellow }

function Get-OcListenerPids {
    $connections = @(Get-NetTCPConnection -LocalPort $script:PORT -State Listen -ErrorAction SilentlyContinue)
    if (@($connections | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') }).Count -gt 0) {
        throw 'OpenClaw port has a non-loopback listener.'
    }
    return @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
}

function Test-OcDaemonAck {
    param($Payload, [string]$Action)
    if ($null -eq $Payload -or $Payload.ok -ne $true -or
        [string]$Payload.action -cne $Action -or
        -not [string]::IsNullOrWhiteSpace([string]$Payload.error)) {
        return $false
    }
    switch ($Action) {
        'stop' { return [string]$Payload.result -ceq 'stopped' }
        'start' { return [string]$Payload.result -cin @('started', 'scheduled') }
        'restart' { return [string]$Payload.result -cin @('restarted', 'scheduled') }
    }
    return $false
}

function Invoke-OcDaemonAction {
    param([ValidateSet('start', 'stop', 'restart')][string]$Action)
    $arguments = if ($Action -eq 'restart') {
        @('gateway', 'restart', '--safe', '--json')
    } else {
        @('gateway', $Action, '--json')
    }
    $raw = & openclaw @arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    try { return Test-OcDaemonAck ($raw | ConvertFrom-Json) $Action }
    catch { return $false }
}

function Test-OcGatewayHealth {
    $raw = & openclaw health --json --verbose 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    try {
        $payload = $raw | ConvertFrom-Json
        return $payload.ok -eq $true -and
            [string]::IsNullOrWhiteSpace([string]$payload.error) -and
            (-not $payload.eventLoop -or $payload.eventLoop.degraded -ne $true)
    } catch { return $false }
}

function Wait-OcGateway {
    param([bool]$Running, [int]$TimeoutSec)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    do {
        $pids = @(Get-OcListenerPids)
        if (-not $Running -and $pids.Count -eq 0) { return @() }
        if ($Running -and $pids.Count -eq 1 -and (Test-OcGatewayHealth)) { return $pids }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'OpenClaw Gateway did not reach the requested state.'
}

function Stop-Gateway {
    $script:OcPreviousPids = @(Get-OcListenerPids)
    if ($script:OcPreviousPids.Count -eq 0) { return }
    if (-not (Invoke-OcDaemonAction stop)) { throw 'OpenClaw official stop failed.' }
    $null = Wait-OcGateway $false 30
}

function Start-Gateway {
    $current = @(Get-OcListenerPids)
    if ($current.Count -eq 1 -and (Test-OcGatewayHealth)) {
        Write-Step '网关已在运行且健康。'
        return
    }
    if ($current.Count -ne 0 -or -not (Invoke-OcDaemonAction start)) {
        throw 'OpenClaw official start failed.'
    }
    $started = @(Wait-OcGateway $true 120)
    if ($script:OcPreviousPids -and
        @($started | Where-Object { $_ -notin $script:OcPreviousPids }).Count -eq 0) {
        throw 'OpenClaw Gateway listener did not transition.'
    }
    Write-Step '网关已启动并通过健康回读。'
}

function Restart-Gateway {
    $before = @(Get-OcListenerPids)
    if ($before.Count -ne 1 -or -not (Invoke-OcDaemonAction restart)) {
        throw 'OpenClaw official restart failed.'
    }
    $after = @(Wait-OcGateway $true 120)
    if (@($after | Where-Object { $_ -notin $before }).Count -eq 0) {
        throw 'OpenClaw Gateway listener did not restart.'
    }
    Write-Step '网关已安全重启并通过健康回读。'
}

# 安全的标量配置写入（经原生 CLI 校验）
function Set-OCConfig($path, $value) {
    & openclaw config set $path $value | Out-Null
    Write-Step "设置 $path = $value"
}
function Get-OCConfig($path) { (& openclaw config get $path 2>$null) }
