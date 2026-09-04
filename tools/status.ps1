<#
.SYNOPSIS  OpenClaw 一屏状态面板（版本/网关/任务/模型/渠道/API/Funnel）。
.EXAMPLE   .\status.ps1
#>
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_common.ps1')
$script:criticalFailures = [Collections.Generic.List[string]]::new()

function Require-Status([bool]$Condition, [string]$Code) {
    if (-not $Condition) { $script:criticalFailures.Add($Code) }
}

function Line($k,$v,$ok=$true){
    Write-Host ("  {0,-18}" -f $k) -NoNewline -ForegroundColor DarkGray
    Write-Host $v -ForegroundColor $(if($ok){'Green'}else{'Yellow'})
}

function Get-JsonResult([string[]]$Arguments) {
    $raw = & openclaw @Arguments 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    try { return $raw | ConvertFrom-Json -Depth 30 }
    catch { return $null }
}

Write-Host "`n  ╔══════════════════ OpenClaw 状态面板 ══════════════════╗`n" -ForegroundColor Green

$version = ((& openclaw --version) 2>$null)
$versionOk = $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$version)
Line '版本' $(if ($versionOk) { $version } else { '读取失败' }) $versionOk
Require-Status $versionOk 'version_unavailable'

$gateway = Get-JsonResult @('gateway','status','--require-rpc','--json')
$gatewayOk = $null -ne $gateway -and $gateway.rpc.ok -eq $true
if ($gatewayOk) {
    Line '网关' ("运行中  v={0}  端口={1}  RPC=ok" -f $gateway.rpc.version,$PORT) $true
} else { Line '网关' '未通过 Gateway RPC 回读' $false }
Require-Status $gatewayOk 'gateway_rpc_unavailable'

$config = Get-JsonResult @('config','validate','--json')
Line '配置' $(if($config.valid){'schema 有效'}else{'schema 无效'}) ($config.valid -eq $true)
Require-Status ($null -ne $config -and $config.valid -eq $true) 'config_schema_invalid'

foreach ($taskExpectation in @(
    @{ Name='OpenClaw Gateway'; Accept=@('Running','Ready') },
    @{ Name='OpenClaw Heartbeat'; Accept=@('Running','Ready') },
    @{ Name='OpenClaw Update'; Accept=@('Disabled') }
)) {
    $st = (Get-ScheduledTask -TaskName $taskExpectation.Name -ErrorAction SilentlyContinue).State
    $taskOk = $st -in $taskExpectation.Accept
    Line ($taskExpectation.Name -replace 'OpenClaw ','任务·') ("$st") $taskOk
    Require-Status $taskOk ("task_state_unexpected:{0}" -f $taskExpectation.Name)
}

$models = Get-JsonResult @('models','status','--json')
$modelOk = $null -ne $models -and -not [string]::IsNullOrWhiteSpace([string]$models.defaultModel)
Line '默认模型' $(if($modelOk){$models.defaultModel}else{'未配置 / 读取失败'}) $modelOk
Require-Status $modelOk 'model_status_unavailable'
$routeGroups = @($models.allowed | ForEach-Object {
    [pscustomobject]@{ Provider=([string]$_ -split '/',2)[0]; Model=[string]$_ }
} | Group-Object Provider | Sort-Object Name)
foreach ($group in $routeGroups) {
    $provider = [string]$group.Name
    $authState = @($models.auth.providers | Where-Object { $_.provider -eq $provider }) | Select-Object -First 1
    $profileCount = if ($null -ne $authState -and $null -ne $authState.profiles) {
        [int]$authState.profiles.count
    } else { 0 }
    $effectiveKind = if ($null -ne $authState) { [string]$authState.effective.kind } else { '' }
    $authConfigured = $profileCount -gt 0 -or $effectiveKind -in @('env','profiles','oauth','token','api_key')
    $authLabel = if ($authConfigured) { 'configured' } else { 'none reported' }
    Line ("模型·$provider") ("routes={0}  auth={1}" -f $group.Count,$authLabel) ($group.Count -gt 0)
}
Line '成本判定' '运行 api.ps1 status（使用官方模型目录 local 字段）' $true

$channels = Get-JsonResult @('channels','status','--json')
Require-Status ($null -ne $channels) 'channel_status_unavailable'
foreach ($ch in 'telegram','feishu','googlechat') {
    $accountsNode = if ($null -ne $channels -and $null -ne $channels.channelAccounts) {
        $channels.channelAccounts.PSObject.Properties[$ch]
    } else { $null }
    $account = if ($null -ne $accountsNode) { @($accountsNode.Value) | Select-Object -First 1 } else { $null }
    if ($null -eq $account) {
        Line ("渠道·$ch") 'disabled / 未配置' $true
        continue
    }
    $parts = @(
        "configured=$([bool]$account.configured)"
        "running=$([bool]$account.running)"
        "lifecycle=$([string]$account.lifecycle)"
    )
    if ($null -ne $account.connected) { $parts += "connected=$([bool]$account.connected)" }
    Line ("渠道·$ch") ($parts -join '  ') ($account.configured -eq $true -and $account.running -eq $true)
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
    Line 'Funnel' $(if($funnelActive){'active（外部 Tailscale 路由）'}else{'off / 未配置'}) $true
} else {
    Line 'Funnel' 'tailscale.exe 未找到' $false
}

Write-Host "`n  ╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Green

if ($script:criticalFailures.Count -gt 0) {
    Write-Host ("  关键状态失败：{0}" -f ($script:criticalFailures -join ', ')) -ForegroundColor Red
    exit 1
}
exit 0
