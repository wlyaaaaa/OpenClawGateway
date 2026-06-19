<#
.SYNOPSIS  快速全局设置 API：key / 模型名称 / 网站(baseUrl)。支持「提供方档案」一键切换。
.DESCRIPTION
  provider 固定为 openai（OpenAI 兼容端点 / openai-responses 类型不变，无需改）。
  仅改三样：API key、默认模型、baseUrl（网站）。改动前自动备份，改动后可自测连通性。

  「提供方档案」：把多家厂商（如 dashscope / deepseek / openai 官方）的 baseUrl+key+model
  存成命名档案，一条命令切换，免去反复输入。档案存于 .secrets\providers.json（已 gitignore）。
.EXAMPLE  .\set-api.ps1 -Show
.EXAMPLE  .\set-api.ps1 -Model qwen3.7-max-2026-06-08
.EXAMPLE  .\set-api.ps1 -BaseUrl "https://dashscope.aliyuncs.com/compatible-mode/v1" -Key "sk-xxx" -Model qwen-max -Test
.EXAMPLE  .\set-api.ps1 -Save dashscope          # 把当前配置存成档案 dashscope
.EXAMPLE  .\set-api.ps1 -Profile dashscope       # 一键切回 dashscope 档案
.EXAMPLE  .\set-api.ps1 -List
#>
param(
    [string]$Key,
    [string]$Model,
    [string]$BaseUrl,
    [string]$Profile,
    [string]$Save,
    [switch]$List,
    [switch]$Show,
    [switch]$Test,
    [string]$Provider = 'openai',
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\_common.ps1')

$secretsDir = Join-Path $PSScriptRoot '.secrets'
$profPath   = Join-Path $secretsDir 'providers.json'

function Read-Profiles { if (Test-Path $profPath) { Get-Content $profPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} } }
function Mask($k) { if ([string]::IsNullOrEmpty($k)) { '(空)' } else { $k.Substring(0,[Math]::Min(8,$k.Length)) + '...(' + $k.Length + ')' } }
function Get-CurrentKey { if (Test-Path $AUTH) { (Get-Content $AUTH -Raw | ConvertFrom-Json).profiles."${Provider}:default".key } else { '' } }
function Show-Current {
    Write-Host "`n当前 API 配置（provider=$Provider，openai 兼容端点，类型不变）:"
    Write-Host ("  网站 baseUrl : " + (Get-OCConfig "models.providers.$Provider.baseUrl")) -ForegroundColor Cyan
    Write-Host ("  默认模型     : " + (Get-OCConfig 'agents.defaults.model.primary')) -ForegroundColor Cyan
    Write-Host ("  API key      : " + (Mask (Get-CurrentKey))) -ForegroundColor Cyan
}

if ($List) {
    $p = Read-Profiles
    Write-Host "`n已保存的提供方档案:"
    $props = $p.PSObject.Properties
    if ($props) { foreach ($e in $props) { Write-Host ("  - {0,-12} {1}  [{2}]  model={3}" -f $e.Name,$e.Value.baseUrl,(Mask $e.Value.key),$e.Value.model) -ForegroundColor Green } }
    else { Write-Info "（暂无档案，用 -Save <名> 保存）" }
    return
}
if ($Show) { Show-Current; return }

# 加载档案
if ($Profile) {
    $pp = (Read-Profiles).$Profile
    if (-not $pp) { Write-Warn2 "档案 '$Profile' 不存在（-List 查看）"; return }
    if (-not $BaseUrl) { $BaseUrl = $pp.baseUrl }
    if (-not $Key)     { $Key     = $pp.key }
    if (-not $Model)   { $Model   = $pp.model }
    Write-Step "已载入档案 '$Profile'"
}

# 保存档案
if ($Save) {
    if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Force $secretsDir | Out-Null }
    $p = Read-Profiles
    $entry = [pscustomobject]@{
        baseUrl = if ($BaseUrl) { $BaseUrl } else { Get-OCConfig "models.providers.$Provider.baseUrl" }
        key     = if ($Key)     { $Key }     else { Get-CurrentKey }
        model   = if ($Model)   { $Model }   else { (Get-OCConfig 'agents.defaults.model.primary') -replace '^.*/','' }
    }
    $p | Add-Member -NotePropertyName $Save -NotePropertyValue $entry -Force
    ($p | ConvertTo-Json -Depth 10) | Set-Content $profPath -Encoding utf8
    Write-Step "已保存档案 '$Save' → $profPath"
}

if (-not ($BaseUrl -or $Key -or $Model)) {
    Show-Current
    if ($Test) { Write-Host "`n连通性 (openclaw models status):" -ForegroundColor Green; & openclaw models status 2>&1 | Select-Object -First 20 }
    return
}

# 备份
$bak = Join-Path (Join-Path $PSScriptRoot 'secrets-backup') ("setapi-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bak | Out-Null
Copy-Item (Join-Path $OC 'openclaw.json') $bak -Force -ErrorAction SilentlyContinue
Copy-Item $AUTH $bak -Force -ErrorAction SilentlyContinue
Write-Info "已备份 → $bak"

Stop-Gateway
if ($BaseUrl) { Set-OCConfig "models.providers.$Provider.baseUrl" $BaseUrl }
if ($Model) {
    $modelId = $Model -replace '^.*/',''
    $models = @(Get-OCConfig "models.providers.$Provider.models" | Out-String | ConvertFrom-Json)
    if ($models.id -notcontains $modelId) {
        Write-Step "自动登记新模型 $modelId"
        $new = [pscustomobject]@{ id=$modelId; name=$modelId; reasoning=$true; input=@('text','image'); contextWindow=131072; contextTokens=96000; maxTokens=32768 }
        $arr = @($models) + $new
        $patch = @{ models = @{ providers = @{ $Provider = @{ models = $arr } } } } | ConvertTo-Json -Depth 100
        $pf = Join-Path $OC 'setapi-reg.patch.json'; $patch | Set-Content $pf -Encoding utf8
        & openclaw config patch --file $pf | Out-Null; Remove-Item $pf -ErrorAction SilentlyContinue
    }
    Set-OCConfig 'agents.defaults.model.primary' "$Provider/$modelId"
}
if ($Key) {
    $auth = if (Test-Path $AUTH) { Get-Content $AUTH -Raw | ConvertFrom-Json } else { [pscustomobject]@{ version=1; profiles=[pscustomobject]@{} } }
    if (-not $auth.profiles."${Provider}:default") {
        $auth.profiles | Add-Member -NotePropertyName "${Provider}:default" -NotePropertyValue ([pscustomobject]@{ type='api_key'; provider=$Provider; key='' }) -Force
    }
    $auth.profiles."${Provider}:default".key = $Key
    ($auth | ConvertTo-Json -Depth 20) | Set-Content $AUTH -Encoding utf8
    Write-Step "已更新 API key"
}
if (-not $NoRestart) { Start-Gateway }
Show-Current
if ($Test) {
    Write-Host "`n连通性测试 (openclaw models status):" -ForegroundColor Green
    & openclaw models status 2>&1 | Select-Object -First 20
}
Write-Host "`n✅ 设置完成。" -ForegroundColor Green
