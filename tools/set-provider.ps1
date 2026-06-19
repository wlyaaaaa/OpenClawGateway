<#
.SYNOPSIS  快速更换 LLM 提供方：API 网站(baseUrl)、Key、模型，一步到位。
.DESCRIPTION
  用于切换大模型供应端（如阿里 DashScope → 其它 OpenAI 兼容端点）。
  改动前自动备份 openclaw.json 与 auth-profiles.json。
.EXAMPLE
  .\set-provider.ps1 -BaseUrl "https://dashscope.aliyuncs.com/compatible-mode/v1" -Key "sk-xxx" -Model qwen3.7-max-2026-06-08
.EXAMPLE
  .\set-provider.ps1 -Provider openai -Key "sk-new" -ShowOnly   # 只看当前，不改
.NOTES  默认 provider=openai（OpenClaw 用此 id 表示“OpenAI 兼容”端点）。
#>
param(
    [string]$Provider = 'openai',
    [string]$BaseUrl,
    [string]$Key,
    [string]$Model,
    [switch]$ShowOnly,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Show-Current {
    Write-Host "`n当前提供方配置（provider=$Provider）:"
    Write-Host ("  baseUrl : " + (Get-OCConfig "models.providers.$Provider.baseUrl")) -ForegroundColor Cyan
    Write-Host ("  primary : " + (Get-OCConfig 'agents.defaults.model.primary')) -ForegroundColor Cyan
    $k = ''
    if (Test-Path $AUTH) { $k = (Get-Content $AUTH -Raw | ConvertFrom-Json).profiles."${Provider}:default".key }
    $masked = if ([string]::IsNullOrEmpty($k)) { '(空 / 安全模式)' } else { $k.Substring(0,[Math]::Min(8,$k.Length)) + '...(' + $k.Length + ' chars)' }
    Write-Host ("  key     : " + $masked) -ForegroundColor Cyan
}

Show-Current
if ($ShowOnly) { return }
if (-not ($BaseUrl -or $Key -or $Model)) { Write-Warn2 "未提供任何 -BaseUrl/-Key/-Model；用 -ShowOnly 只看。"; return }

# 备份
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bak = Join-Path 'E:\OpenClawGateway\secrets-backup' "provider-$stamp"
New-Item -ItemType Directory -Force $bak | Out-Null
Copy-Item (Join-Path $OC 'openclaw.json') $bak -Force -ErrorAction SilentlyContinue
Copy-Item $AUTH $bak -Force -ErrorAction SilentlyContinue
Write-Info "已备份 → $bak"

Stop-Gateway
if ($BaseUrl) { Set-OCConfig "models.providers.$Provider.baseUrl" $BaseUrl }
if ($Model)   { $full = if ($Model -match '/') { $Model } else { "$Provider/$Model" }; Set-OCConfig 'agents.defaults.model.primary' $full }
if ($Key) {
    $auth = if (Test-Path $AUTH) { Get-Content $AUTH -Raw | ConvertFrom-Json } else { [pscustomobject]@{ version=1; profiles=[pscustomobject]@{} } }
    if (-not $auth.profiles."${Provider}:default") {
        $auth.profiles | Add-Member -NotePropertyName "${Provider}:default" -NotePropertyValue ([pscustomobject]@{ type='api_key'; provider=$Provider; key='' }) -Force
    }
    $auth.profiles."${Provider}:default".key = $Key
    ($auth | ConvertTo-Json -Depth 20) | Set-Content $AUTH -Encoding utf8
    Write-Step "已更新 $Provider 的 API key"
}
if (-not $NoRestart) { Start-Gateway }
Write-Host "`n✅ 提供方已更新。" -ForegroundColor Green
Show-Current
