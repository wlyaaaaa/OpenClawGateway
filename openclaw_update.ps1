# =====================================================================
#  OpenClaw Gateway Auto-Update Helper (channel-aware, China-resilient)
#  - Reads update.channel from config (stable/beta/dev) -> npm dist-tag
#  - Updates ONLY the npm package (no `openclaw update` doctor), so the
#    custom silent-boot scheduled task is never clobbered.
#  - Restarts the Gateway task and runs a health check.
#  Log: E:\OpenClawGateway\logs\openclaw_update.log
#  Run elevated (Administrator) — invoked weekly by the "OpenClaw Update" task.
# =====================================================================
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $root) { $root = 'E:\OpenClawGateway' }
$logDir = Join-Path $root 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'openclaw_update.log'

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $line
}

Log "=== OpenClaw Update — start ==="

# Elevation check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Log "[ERROR] Must run as Administrator."
    exit 1
}

$taskName = 'OpenClaw Gateway'
$port = 18789

try {
    # 1. Resolve channel -> npm dist-tag
    $channel = 'stable'
    try { $channel = (& openclaw config get update.channel 2>$null).Trim() } catch {}
    switch ($channel) {
        'beta' { $tag = 'beta' }
        'dev'  { $tag = 'dev'  }
        default { $tag = 'latest'; $channel = 'stable' }
    }
    Log "channel=$channel -> npm tag=@$tag"

    # 2. Current vs target version
    $current = ''
    if (((& openclaw --version 2>$null) | Out-String) -match '(\d+\.\d+\.\d+[\w.-]*)') { $current = $matches[1] }
    $target  = (& npm view "openclaw@$tag" version 2>$null)
    Log "current=$current  target(@$tag)=$target"
    if (-not $target) { Log "[WARN] could not resolve target version (registry unreachable?). Aborting."; exit 1 }
    if ($current -eq $target) { Log "[OK] already on $target. Nothing to do."; Log "=== done ==="; exit 0 }

    # 3. Update the npm package ONLY (no doctor -> custom task preserved)
    Log "running: npm install -g openclaw@$tag"
    $npmOut = & npm install -g "openclaw@$tag" 2>&1
    Log ("npm: " + ($npmOut -join ' | '))
    $new = (& openclaw --version 2>$null)
    Log "installed version now: $new"

    # 4. Restart the Gateway task to load the new build
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        $p = (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 3
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
        Log "restarted '$taskName'"
    } else { Log "[WARN] task '$taskName' not found; skip restart" }

    # 5. Health check
    $conn = Test-NetConnection -ComputerName '127.0.0.1' -Port $port -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) { Log "[OK] gateway healthy on $port after update" }
    else { Log "[ERROR] port $port unresponsive after update — see C:\Users\10979\.openclaw\gateway.log" }
}
catch {
    Log "[ERROR] update failed: $_"
    exit 1
}
Log "=== done ==="
