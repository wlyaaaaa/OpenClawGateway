# =====================================================================
#  OpenClaw Gateway Heartbeat Watchdog
#  Checks the official Gateway health/RPC surface. If unhealthy, uses the
#  OpenClaw 2.0 lifecycle commands to start or queue a restart.
#  Log output: E:\Projects\Tools\OpenClawGateway\logs\openclaw_heartbeat.log
# =====================================================================
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $root) { $root = 'E:\Projects\Tools\OpenClawGateway' }
$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'openclaw_heartbeat.log'
. (Join-Path $root 'tools\_common.ps1')

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $line
}

try {
    Log 'Checking OpenClaw Gateway health...'
    if (Test-OcGatewayHealth) {
        Log '[OK] Gateway health and event loop are normal.'
        exit 0
    }

    $pids = @(Get-OcListenerPids)
    if ($pids.Count -eq 0) {
        Log '[WARN] Gateway is not listening; requesting official start.'
        Start-Gateway
    } elseif ($pids.Count -eq 1) {
        Log '[WARN] Gateway listener is unhealthy; requesting official safe restart.'
        Restart-Gateway
    } else {
        throw "unexpected Gateway listener count: $($pids.Count)"
    }

    if (Test-OcGatewayHealth) {
        Log '[OK] Gateway recovered and passed health readback.'
    } else {
        Log '[INFO] Recovery request accepted; a deferred restart remains queued.'
    }
}
catch {
    Log "[ERROR] Gateway recovery failed: $($_.Exception.Message)"
    exit 1
}
