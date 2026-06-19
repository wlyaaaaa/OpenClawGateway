<#
.SYNOPSIS  OpenClaw 一屏状态面板（版本/网关/任务/模型/渠道/API/Funnel）。
.EXAMPLE   .\status.ps1
#>
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_common.ps1')

function Line($k,$v,$ok=$true){
    Write-Host ("  {0,-14}" -f $k) -NoNewline -ForegroundColor DarkGray
    Write-Host $v -ForegroundColor $(if($ok){'Green'}else{'Yellow'})
}

Write-Host "`n  ╔══════════════════ OpenClaw 状态面板 ══════════════════╗`n" -ForegroundColor Green

Line '版本' ((& openclaw --version) 2>$null)

$c = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($c) {
    $p = Get-Process -Id $c.OwningProcess
    Line '网关' ("运行中  pid={0}  RAM={1}MB  端口={2}" -f $p.Id,[math]::Round($p.WorkingSet64/1MB),$PORT) $true
} else { Line '网关' '未运行（端口无监听）' $false }

foreach ($t in 'OpenClaw Gateway','OpenClaw Heartbeat','OpenClaw Update') {
    $st = (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue).State
    Line ($t -replace 'OpenClaw ','任务·') ("$st") ($st -ne 'Disabled')
}

Line '默认模型' (Get-OCConfig 'agents.defaults.model.primary')
Line '思考等级' (Get-OCConfig 'agents.defaults.thinkingDefault')

$k = ''
if (Test-Path $AUTH) { $k = (Get-Content $AUTH -Raw | ConvertFrom-Json).profiles.'openai:default'.key }
if ([string]::IsNullOrEmpty($k)) { Line 'API 模式' '安全模式（key 已清空，零花费）' $false }
else { Line 'API 模式' ('已启用（key ' + $k.Substring(0,[Math]::Min(6,$k.Length)) + '...）') $true }

foreach ($ch in 'telegram','feishu','googlechat') {
    Line ("渠道·$ch") (Get-OCConfig "channels.$ch.enabled")
}

$funnel = & 'C:\Program Files\Tailscale\tailscale.exe' funnel status 2>$null | Select-Object -First 1
Line 'Funnel' $(if($funnel -match 'http'){$funnel}else{'off / 未配置'})

Write-Host "`n  ╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Green
