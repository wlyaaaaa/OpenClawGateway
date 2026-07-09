# =====================================================================
#  OpenClaw Gateway Safe Asynchronous Restart Helper
#  Escapes the scheduled task's process tree to avoid self-termination.
#  Log: %USERPROFILE%\.openclaw\logs\OpenClawGateway\openclaw_heartbeat.log
# =====================================================================
$ErrorActionPreference = 'Stop'
$taskName = 'OpenClaw Gateway'
$port = 18789

$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }
$logFile = Join-Path $logDir 'openclaw_heartbeat.log'

function Log([string]$m) {
    $line = "{0}  [RESTART] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
}

Log "Initiating safe async gateway restart..."

# Use WMI to launch a completely detached powershell process that waits, stops the task, and starts it.
# This escapes the scheduled task's process tree, preventing it from being killed when Stop-ScheduledTask is run.
$command = "powershell.exe -NoProfile -WindowStyle Hidden -Command `& { Start-Sleep -Seconds 2; Stop-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; Start-ScheduledTask -TaskName '$taskName'; }"

Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList $command | Out-Null

Log "Async restart process spawned successfully via WMI."
