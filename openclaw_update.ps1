# =====================================================================
#  OpenClaw Gateway Manual Update Helper (channel-aware, China-resilient)
#  - Reads update.channel from config (stable/beta/dev) -> npm dist-tag
#  - Updates ONLY the npm package (no `openclaw update` doctor), so the
#    custom silent-boot scheduled task is never clobbered.
#  - Restarts the Gateway task and runs a health check.
#  Log: %USERPROFILE%\.openclaw\logs\OpenClawGateway\openclaw_update.log
#  Run elevated (Administrator) when manually updating. The "OpenClaw Update"
#  task is registered but intentionally Disabled by bootstrap/setup.ps1.
# =====================================================================
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $root) { $root = 'E:\Projects\Tools\OpenClawGateway' }
$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'openclaw_update.log'

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $line
}

Log "=== OpenClaw manual update - start ==="

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

    # 3.5 SELF-HEAL: re-assert critical config (new versions may migrate/reset it)
    #     关键：api=openai-completions 一旦被改回 responses，工具/技能会 400 失败
    $api = ((& openclaw config get models.providers.openai.api 2>$null) | Out-String).Trim()
    if ($api -ne 'openai-completions') {
        & openclaw config set models.providers.openai.api openai-completions 2>$null | Out-Null
        Log "[SELF-HEAL] re-asserted api=openai-completions (was: $api)"
    } else { Log "[SELF-HEAL] api=openai-completions OK" }
    $tg = ((& openclaw config get channels.telegram.allowFrom 2>$null) | Out-String)
    if ($tg -match '\*') { Log "[SELF-HEAL][WARN] telegram allowFrom 含 '*'(疑被 doctor 补回)，请手动收敛" }
    if (((& openclaw config validate 2>&1) | Out-String) -match 'invalid') { Log "[SELF-HEAL][ERR] 更新后 config 无效，请检查" }

    # 4. Restart the Gateway task to load the new build using the safe WMI escape helper
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Log "Spawning async gateway restart helper via restart_gateway.ps1..."
        $restartScript = Join-Path $root 'tools\restart_gateway.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $restartScript
        Log "Async restart process spawned successfully."
    } else { Log "[WARN] task '$taskName' not found; skip restart" }

    # 5. Health check (polling with 15s timeout to allow async restart to complete)
    Log "Waiting for gateway to restart and listen on port $port..."
    $healthy = $false
    for ($i = 1; $i -le 15; $i++) {
        Start-Sleep -Seconds 1
        $conn = Test-NetConnection -ComputerName '127.0.0.1' -Port $port -WarningAction SilentlyContinue
        if ($conn.TcpTestSucceeded) {
            $healthy = $true
            break
        }
    }
    if ($healthy) { Log "[OK] gateway healthy on $port after update" }
    else { Log "[ERROR] port $port unresponsive after update - see $(Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'gateway.log')" }
}
catch {
    Log "[ERROR] update failed: $_"
    exit 1
}
Log "=== done ==="
