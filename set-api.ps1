<#
.SYNOPSIS  快速全局设置 API：key / 模型名称 / 网站(baseUrl)。支持「提供方档案」一键切换。
.DESCRIPTION
  provider 固定为 openai；api=openai-completions 命门不变。
  仅改三样：API key、默认模型、baseUrl（网站）。改动前自动备份，改动后可自测连通性。
.EXAMPLE  .\set-api.ps1 -BaseUrl "https://dashscope.aliyuncs.com/compatible-mode/v1" -Key "sk-xxx" -Model "qwen3.7-plus" -Test
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

function Get-CurrentKey { 
    $k = Get-OCConfig "models.providers.$Provider.apiKey"
    if ($k) { return $k } else { return '' }
}

function Show-Current {
    Write-Host "`n当前 API 配置（provider=$Provider，openai 兼容端点）:"
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
    if ($Test) { 
        Write-Host "`n连通性 (openclaw models status):" -ForegroundColor Green
        cmd /c "openclaw models status"
    }
    return
}

# 备份
$bak = Join-Path (Join-Path $PSScriptRoot 'secrets-backup') ("setapi-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bak | Out-Null
Copy-Item (Join-Path $OC 'openclaw.json') $bak -Force -ErrorAction SilentlyContinue
Write-Info "已备份 → $bak"

Stop-Gateway

# 打造万无一失的配置大补丁
$patchObject = [ordered]@{
    models = @{ providers = @{ $Provider = @{} } }
    agents = @{ defaults = @{ model = @{}; models = @{} } }
}

if ($BaseUrl) { $patchObject.models.providers.$Provider.baseUrl = $BaseUrl }
if ($Key) { $patchObject.models.providers.$Provider.apiKey = $Key }
if ($Model) {
    $modelId = $Model -replace '^.*/',''
    $targetKey = "$Provider/$modelId"
    $patchObject.agents.defaults.model.primary = $targetKey
    $patchObject.agents.defaults.models.$targetKey = @{}
}

# 将大补丁整合成单次下发
$finalPatch = $patchObject | ConvertTo-Json -Depth 10
$pf = Join-Path $PSScriptRoot 'setapi-unified.patch.json'
$finalPatch | Set-Content $pf -Encoding utf8
& openclaw config patch --file $pf | Out-Null
Remove-Item $pf -ErrorAction SilentlyContinue
Write-Step "配置补丁已成功安全合并"

if (-not $NoRestart) { Start-Gateway }
Show-Current

# 核心修复：使用 cmd /c 运行测试，彻底隔离 stderr，防止 PS 5.1 误报终止
if ($Test) {
    Write-Host "`n连通性测试 (openclaw models status):" -ForegroundColor Green
    cmd /c "openclaw models status"
}
Write-Host "`n✅ 设置完成。" -ForegroundColor Green