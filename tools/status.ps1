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

function Get-JsonResult([string[]]$Arguments) {
    $raw = & openclaw @Arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    try { return $raw | ConvertFrom-Json -Depth 30 }
    catch { return $null }
}

Write-Host "`n  ╔══════════════════ OpenClaw 状态面板 ══════════════════╗`n" -ForegroundColor Green

Line '版本' ((& openclaw --version) 2>$null)

$gateway = Get-JsonResult @('gateway','status','--require-rpc','--json')
$gatewayOk = $null -ne $gateway -and $gateway.rpc.ok -eq $true
if ($gatewayOk) {
    Line '网关' ("运行中  v={0}  端口={1}  RPC=ok" -f $gateway.rpc.version,$PORT) $true
} else { Line '网关' '未通过 Gateway RPC 回读' $false }

$config = Get-JsonResult @('config','validate','--json')
Line '配置' $(if($config.valid){'schema 有效'}else{'schema 无效'}) ($config.valid -eq $true)

foreach ($t in 'OpenClaw Gateway','OpenClaw Heartbeat','OpenClaw Update') {
    $st = (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue).State
    Line ($t -replace 'OpenClaw ','任务·') ("$st") ($st -ne 'Disabled')
}

$models = Get-JsonResult @('models','status','--json')
Line '默认模型' $(if($models.defaultModel){$models.defaultModel}else{'未配置'}) (-not [string]::IsNullOrWhiteSpace([string]$models.defaultModel))
foreach ($provider in @('qwen','deepseek')) {
    $routeCount = @($models.allowed | Where-Object { $_ -like "$provider/*" }).Count
    $auth = @($models.auth.providers | Where-Object { $_.provider -eq $provider -and $_.profiles.apiKey -gt 0 }).Count -gt 0
    Line ("模型·$provider") ("routes={0}  auth={1}" -f $routeCount,$(if($auth){'configured'}else{'missing'})) ($routeCount -gt 0 -and $auth)
}
$localRouteCount = @($models.allowed | Where-Object { $_ -like 'ollama5090d/*' }).Count
Line '模型·local' ("ollama5090d routes={0}" -f $localRouteCount) ($localRouteCount -gt 0)

foreach ($ch in 'telegram','feishu','googlechat') {
    Line ("渠道·$ch") (Get-OCConfig "channels.$ch.enabled")
}

$tailscale = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $tailscale -and (Test-Path 'C:\Program Files\Tailscale\tailscale.exe')) {
    $tailscale = [pscustomobject]@{ Source = 'C:\Program Files\Tailscale\tailscale.exe' }
}
if ($tailscale) {
    $funnelRaw = & $tailscale.Source serve status --json 2>$null | Out-String
    try { $funnel = $funnelRaw | ConvertFrom-Json -Depth 10 }
    catch { $funnel = $null }
    $funnelActive = $null -ne $funnel -and
        @($funnel.AllowFunnel.PSObject.Properties | Where-Object { $_.Value -eq $true }).Count -gt 0
    Line 'Funnel' $(if($funnelActive){'active（外部 Tailscale 路由）'}else{'off / 未配置'}) $funnelActive
} else {
    Line 'Funnel' 'tailscale.exe 未找到' $false
}

Write-Host "`n  ╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Green
