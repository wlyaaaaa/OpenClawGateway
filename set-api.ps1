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

$secretsDir = Join-Path $OC '.secrets'
$profPath   = Join-Path $secretsDir 'providers.json'

function Read-Profiles { 
    if (Test-Path $profPath) { 
        return (Get-Content $profPath -Raw | ConvertFrom-Json) 
    } else { 
        return [pscustomobject]@{} 
    } 
}
function Mask($k) { 
    if ([string]::IsNullOrEmpty($k)) { 
        return '(empty)' 
    } else { 
        return ($k.Substring(0,[Math]::Min(8,$k.Length)) + '...(' + $k.Length + ')') 
    } 
}

function Get-CurrentKey { 
    $authFile = Join-Path $OC 'auth-profiles.json'
    if (Test-Path $authFile) {
        try {
            $auth = Get-Content $authFile -Raw | ConvertFrom-Json
            $profileName = "${Provider}:default"
            if ($auth.profiles.$profileName) {
                $k = $auth.profiles.$profileName.key
                if ($k) { return $k }
            }
        } catch {}
    }
    $k = Get-OCConfig "models.providers.$Provider.apiKey"
    if ($k) { return $k } else { return '' }
}

function Show-Current {
    Write-Host "`nCurrent API config (provider=$Provider, openai compatible endpoint):"
    Write-Host ("  Base URL     : " + (Get-OCConfig "models.providers.$Provider.baseUrl")) -ForegroundColor Cyan
    Write-Host ("  Default Model: " + (Get-OCConfig 'agents.defaults.model.primary')) -ForegroundColor Cyan
    Write-Host ("  API Key      : " + (Mask (Get-CurrentKey))) -ForegroundColor Cyan
}

if ($List) {
    $p = Read-Profiles
    Write-Host "`nSaved provider profiles:"
    $props = $p.PSObject.Properties
    if ($props) { foreach ($e in $props) { Write-Host ("  - {0,-12} {1}  [{2}]  model={3}" -f $e.Name,$e.Value.baseUrl,(Mask $e.Value.key),$e.Value.model) -ForegroundColor Green } }
    else { Write-Info "(No profiles saved, use -Save <Name> to save one)" }
    return
}
if ($Show) { Show-Current; return }

# 加载档案
if ($Profile) {
    $pp = (Read-Profiles).$Profile
    if (-not $pp) { Write-Warn2 "Profile '$Profile' does not exist (-List to view all)"; return }
    if (-not $BaseUrl) { $BaseUrl = $pp.baseUrl }
    if (-not $Key)     { $Key     = $pp.key }
    if (-not $Model)   { $Model   = $pp.model }
    Write-Step "Loaded profile '$Profile'"
}

# 保存档案
if ($Save) {
    if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Force $secretsDir | Out-Null }
    $p = Read-Profiles
    
    # Evaluate values using subexpressions to avoid PS 5.1 syntax errors
    $valBaseUrl = $(if ($BaseUrl) { $BaseUrl } else { Get-OCConfig "models.providers.$Provider.baseUrl" })
    $valKey     = $(if ($Key)     { $Key }     else { Get-CurrentKey })
    $valModel   = $(if ($Model)   { $Model }   else { (Get-OCConfig 'agents.defaults.model.primary') -replace '^.*/','' })
    
    $entry = [pscustomobject]@{
        baseUrl = $valBaseUrl
        key     = $valKey
        model   = $valModel
    }
    $p | Add-Member -NotePropertyName $Save -NotePropertyValue $entry -Force
    
    # Save without BOM using .NET WriteAllText
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $jsonProfiles = $p | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($profPath, $jsonProfiles, $utf8NoBom)
    Write-Step "Saved profile '$Save' -> $profPath"
}

if (-not ($BaseUrl -or $Key -or $Model)) {
    Show-Current
    if ($Test) { 
        Write-Host "`nConnectivity (openclaw models status):" -ForegroundColor Green
        cmd /c "openclaw models status"
    }
    return
}

# 备份
$bak = Join-Path (Join-Path $OC 'secrets-backup') ("setapi-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bak | Out-Null
Copy-Item (Join-Path $OC 'openclaw.json') $bak -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $OC 'auth-profiles.json') $bak -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $OC 'config.yml') $bak -Force -ErrorAction SilentlyContinue
$clinePath = Join-Path $env:USERPROFILE '.cline\data\settings\providers.json'
Copy-Item $clinePath $bak -Force -ErrorAction SilentlyContinue
Write-Info "Backed up configuration files -> $bak"

Stop-Gateway

# 打造万无一失的配置大补丁 (Variable keys quoted to satisfy PS 5.1)
$patchObject = [ordered]@{
    models = @{ providers = @{ "$Provider" = @{} } }
    agents = @{ defaults = @{ model = @{}; models = @{} } }
    auth   = @{ profiles = @{ "${Provider}:default" = @{ provider = $Provider; mode = "api_key" } } }
}

if ($BaseUrl) { $patchObject.models.providers."$Provider".baseUrl = $BaseUrl }
if ($Key) { $patchObject.models.providers."$Provider".apiKey = $Key }
if ($Model) {
    $modelId = $Model -replace '^.*/',''
    $targetKey = "$Provider/$modelId"
    $patchObject.agents.defaults.model.primary = $targetKey
    $patchObject.agents.defaults.models[$targetKey] = @{}
}

# 将大补丁整合成单次下发 (BOM-free UTF-8)
$finalPatch = $patchObject | ConvertTo-Json -Depth 10
$pf = Join-Path $PSScriptRoot 'setapi-unified.patch.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($pf, $finalPatch, $utf8NoBom)
& openclaw config patch --file $pf | Out-Null
Remove-Item $pf -ErrorAction SilentlyContinue
Write-Step "Configuration patch merged successfully (BOM-Free)"

# 2. 更新 auth-profiles.json 中的 API key (BOM-free UTF-8)
$authFile = Join-Path $OC 'auth-profiles.json'
if ($Key) {
    try {
        $auth = [pscustomobject]@{ version = 1; profiles = [ordered]@{} }
        if (Test-Path $authFile) {
            $rawAuth = Get-Content $authFile -Raw
            if ($rawAuth) { $auth = $rawAuth | ConvertFrom-Json }
        }
        if (-not $auth.profiles) { $auth | Add-Member -NotePropertyName "profiles" -NotePropertyValue (New-Object PSObject) }
        $profileName = "${Provider}:default"
        if ($auth.profiles.$profileName) {
            $auth.profiles.$profileName.key = $Key
        } else {
            $auth.profiles | Add-Member -NotePropertyName $profileName -NotePropertyValue ([pscustomobject]@{
                type = 'api_key'
                provider = $Provider
                key = $Key
            }) -Force
        }
        $json = $auth | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($authFile, $json, $utf8NoBom)
        Write-Step "Updated auth profile key for $profileName in auth-profiles.json (BOM-Free)"
        
        # 2b. 同步更新 SQLite 数据库以确保即时生效
        $pyHelper = Join-Path $PSScriptRoot 'tools\update_sqlite_profiles.py'
        if (Test-Path $pyHelper) {
            python $pyHelper $Provider $Key | Out-Null
            Write-Step "Synchronized credentials directly to SQLite store"
        }
    } catch {
        Write-Warn2 "Failed to update auth-profiles.json: $_"
    }
}

# 3. 同步 config.yml (BOM-free UTF-8)
$configYml = Join-Path $OC 'config.yml'
if (Test-Path $configYml) {
    try {
        $content = Get-Content $configYml -Raw
        $targetModelId = $(if ($Model) { $Model -replace '^.*/','' } else { Get-OCConfig 'agents.defaults.model.primary' -replace '^.*/','' })
        $targetBaseUrl = $(if ($BaseUrl) { $BaseUrl } else { Get-OCConfig "models.providers.$Provider.baseUrl" })
        $targetKey = $(if ($Key) { $Key } else { Get-CurrentKey })
        
        $content = $content -replace '(?m)^\s*provider:\s*["'']?[\w.-]+["'']?', "  provider: `"$Provider`""
        if ($targetKey) {
            $content = $content -replace '(?m)^\s*api_key:\s*["'']?[^"''\r\n]+["'']?', "  api_key: `"$targetKey`""
        }
        if ($targetBaseUrl) {
            $content = $content -replace '(?m)^\s*base_url:\s*["'']?[^"''\r\n]+["'']?', "  base_url: `"$targetBaseUrl`""
        }
        if ($targetModelId) {
            $content = $content -replace '(?m)^\s*model:\s*["'']?[\w.-]+["'']?', "  model: `"$targetModelId`""
        }
        
        [System.IO.File]::WriteAllText($configYml, $content, $utf8NoBom)
        Write-Step "Synchronized config.yml configuration (BOM-Free)"
    } catch {
        Write-Warn2 "Failed to sync config.yml: $_"
    }
}

# 4. 同步 Cline providers.json (BOM-free UTF-8)
if (Test-Path $clinePath) {
    try {
        $cline = Get-Content $clinePath -Raw | ConvertFrom-Json
        if ($cline.providers.'openai-compatible') {
            $targetModelId = $(if ($Model) { $Model -replace '^.*/','' } else { Get-OCConfig 'agents.defaults.model.primary' -replace '^.*/','' })
            $targetBaseUrl = $(if ($BaseUrl) { $BaseUrl } else { Get-OCConfig "models.providers.$Provider.baseUrl" })
            $targetKey = $(if ($Key) { $Key } else { Get-CurrentKey })
            
            if ($targetModelId) { $cline.providers.'openai-compatible'.settings.model = $targetModelId }
            if ($targetBaseUrl) { $cline.providers.'openai-compatible'.settings.baseUrl = $targetBaseUrl }
            if ($targetKey) { $cline.providers.'openai-compatible'.settings.apiKey = $targetKey }
            $cline.providers.'openai-compatible'.updatedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
            
            $json = $cline | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($clinePath, $json, $utf8NoBom)
            Write-Step "Synchronized Cline providers.json configuration (BOM-Free)"
        }
    } catch {
        Write-Warn2 "Failed to sync Cline providers.json: $_"
    }
}

if (-not $NoRestart) { Start-Gateway }
Show-Current

# 核心修复：使用 cmd /c 运行测试，彻底隔离 stderr，防止 PS 5.1 误报终止
if ($Test) {
    Write-Host "`nConnectivity test (openclaw models status):" -ForegroundColor Green
    cmd /c "openclaw models status"
}
Write-Host "`nSetup completed successfully." -ForegroundColor Green
