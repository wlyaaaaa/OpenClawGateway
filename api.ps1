<#
.SYNOPSIS  一键开关 OpenClaw 的大模型 API（成本安全模式）。
.DESCRIPTION
  on     ＝ 还原 key + 保持 IM 渠道开关 + funnel（机器人可用）
  off    ＝ 清空 key + 保持 IM 渠道开关 + 关 funnel（零花费，API 安全模式）
  toggle ＝ 自动判别当前状态并翻转（默认）
  status ＝ 查看当前状态
.EXAMPLE  .\api.ps1 on
.EXAMPLE  .\api.ps1        # 不带参数＝toggle
.EXAMPLE  .\api.ps1 status
#>
param([Parameter(Position=0)][ValidateSet('on','off','toggle','status','')]$Action='')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\_common.ps1')
$root = $PSScriptRoot

function Get-ApiState {
    $k = ''
    if (Test-Path $AUTH) { $k = (Get-Content $AUTH -Raw | ConvertFrom-Json).profiles.'openai:default'.key }
    if ([string]::IsNullOrEmpty($k)) { 'off' } else { 'on' }
}

$cur = Get-ApiState
Write-Host ("当前 API: " + $cur.ToUpper()) -ForegroundColor $(if($cur -eq 'on'){'Green'}else{'Yellow'})

if ($Action -eq 'status') { & (Join-Path $root 'tools\status.ps1'); return }
if ($Action -eq '' -or $Action -eq 'toggle') { $Action = if ($cur -eq 'on') { 'off' } else { 'on' } }

if ($Action -eq $cur) { Write-Info "已经是 $Action，无需变更。"; return }

switch ($Action) {
    'on'  { Write-Host "`n→ 开启 API ..." -ForegroundColor Green;  & (Join-Path $root 'enable-openclaw-api.ps1') }
    'off' { Write-Host "`n→ 关闭 API ..." -ForegroundColor Yellow; & (Join-Path $root 'disable-openclaw-api.ps1') }
}
