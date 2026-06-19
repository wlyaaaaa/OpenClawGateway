# =====================================================================
#  _common.ps1 — OpenClaw 工具集公共函数（被各脚本 dot-source 引用）
# =====================================================================
$script:OC   = 'C:\Users\10979\.openclaw'
$script:TASK = 'OpenClaw Gateway'
$script:PORT = 18789
$script:AUTH = Join-Path $OC 'auth-profiles.json'

function Write-Step($m){ Write-Host "  $m" -ForegroundColor Green }
function Write-Info($m){ Write-Host "  $m" -ForegroundColor DarkGray }
function Write-Warn2($m){ Write-Host "  ! $m" -ForegroundColor Yellow }

function Stop-Gateway {
    Stop-ScheduledTask -TaskName $script:TASK -ErrorAction SilentlyContinue
    $p = (Get-NetTCPConnection -LocalPort $script:PORT -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Start-Gateway {
    Start-ScheduledTask -TaskName $script:TASK -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 9
    $c = Get-NetTCPConnection -LocalPort $script:PORT -State Listen -ErrorAction SilentlyContinue
    if ($c) { Write-Step "网关已重启，监听 $script:PORT (pid=$($c.OwningProcess))" }
    else    { Write-Warn2 "网关暂未监听 $script:PORT，查看 gateway.log" }
}

function Restart-Gateway { Stop-Gateway; Start-Gateway }

# 安全的标量配置写入（经原生 CLI 校验）
function Set-OCConfig($path, $value) {
    & openclaw config set $path $value | Out-Null
    Write-Step "设置 $path = $value"
}
function Get-OCConfig($path) { (& openclaw config get $path 2>$null) }
