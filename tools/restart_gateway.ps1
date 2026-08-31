# =====================================================================
#  OpenClaw Gateway 2.0 Safe Restart Helper
#  Deferred/coalesced requests return immediately and complete after the
#  requesting work drains; scheduled requests wait for PID + health transition.
#  Log: %USERPROFILE%\.openclaw\logs\OpenClawGateway\openclaw_heartbeat.log
# =====================================================================
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }
$logFile = Join-Path $logDir 'openclaw_heartbeat.log'

function Log([string]$m) {
    $line = "{0}  [RESTART] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
}

Log 'Requesting official OpenClaw 2.0 safe restart...'
try {
    Restart-Gateway
    Log 'Safe restart was accepted by OpenClaw.'
}
catch {
    Log "Safe restart failed: $($_.Exception.Message)"
    exit 1
}
exit 0
