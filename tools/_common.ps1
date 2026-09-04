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
    if ($null -eq $Payload) { return $false }
    $ok = $Payload.PSObject.Properties['ok']
    $errorProperty = $Payload.PSObject.Properties['error']
    $actionProperty = $Payload.PSObject.Properties['action']
    $resultProperty = $Payload.PSObject.Properties['result']
    $actionValue = if ($null -ne $actionProperty) { [string]$actionProperty.Value } else { '' }
    $resultValue = if ($null -ne $resultProperty) { [string]$resultProperty.Value } else { '' }
    if ($null -eq $ok -or $ok.Value -ne $true -or
        ($null -ne $errorProperty -and
         -not [string]::IsNullOrWhiteSpace([string]$errorProperty.Value))) {
        return $false
    }
    if ($Action -eq 'restart') {
        if ($actionValue -ceq 'restart' -and $resultValue -ceq 'restarted') {
            return $true
        }
        $restart = $Payload.PSObject.Properties['restart']
        if ($null -eq $restart -or $null -eq $restart.Value) { return $false }
        $restartOk = $restart.Value.PSObject.Properties['ok']
        $restartPid = $restart.Value.PSObject.Properties['pid']
        $restartReason = $restart.Value.PSObject.Properties['reason']
        return $resultValue -cin @('scheduled', 'deferred', 'coalesced') -and
            $null -ne $restartOk -and $restartOk.Value -eq $true -and
            $null -ne $restartPid -and [int]$restartPid.Value -gt 0 -and
            $null -ne $restartReason -and
            [string]$restartReason.Value -ceq 'gateway.restart.safe'
    }
    if ($actionValue -cne $Action) { return $false }
    switch ($Action) {
        'stop' { return $resultValue -ceq 'stopped' }
        'start' { return $resultValue -cin @('started', 'scheduled') }
    }
    return $false
}

function Invoke-OcDaemonAction {
    param([ValidateSet('start', 'stop', 'restart')][string]$Action)
    $script:OcLastDaemonResult = $null
    $arguments = if ($Action -eq 'restart') {
        @('gateway', 'restart', '--safe', '--json')
    } elseif ($Action -eq 'stop') {
        @('gateway', 'stop', '--force', '--json')
    } else {
        @('gateway', $Action, '--json')
    }
    $raw = & openclaw @arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    try {
        $script:OcLastDaemonResult = $raw | ConvertFrom-Json
        return Test-OcDaemonAck $script:OcLastDaemonResult $Action
    }
    catch { return $false }
}

function Test-OcGatewayHealth {
    $raw = & openclaw health --json --verbose 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    try {
        $payload = $raw | ConvertFrom-Json
        $errorProperty = $payload.PSObject.Properties['error']
        $eventLoop = $payload.PSObject.Properties['eventLoop']
        return $payload.ok -eq $true -and
            ($null -eq $errorProperty -or
             [string]::IsNullOrWhiteSpace([string]$errorProperty.Value)) -and
            ($null -eq $eventLoop -or $eventLoop.Value.degraded -ne $true)
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
    if ([string]$script:OcLastDaemonResult.result -cin @('deferred', 'coalesced')) {
        Write-Step '网关重启已排队；当前调用结束后由外部状态回读验收。'
        return
    }
    $after = @(Wait-OcGateway $true 120)
    if (@($after | Where-Object { $_ -notin $before }).Count -eq 0) {
        throw 'OpenClaw Gateway listener did not restart.'
    }
    Write-Step '网关已重启并通过健康回读。'
}
