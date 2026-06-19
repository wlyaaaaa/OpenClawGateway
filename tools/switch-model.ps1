<#
.SYNOPSIS  快速切换 OpenClaw 默认模型（可选同时设思考等级）。
.EXAMPLE   .\switch-model.ps1 -List
.EXAMPLE   .\switch-model.ps1 -Model qwen3.7-max-2026-06-08 -Thinking max
.EXAMPLE   .\switch-model.ps1 -Model qwen4-max-2026-12-01 -Register   # 注册并切到新版本模型
.NOTES     新模型上线时用 -Register 自动登记到 provider，再设为默认。
#>
param(
    [string]$Model,
    [ValidateSet('off','minimal','low','medium','high','adaptive','max')][string]$Thinking,
    [string]$Provider = 'openai',
    [switch]$Register,
    [switch]$List,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

if ($List) {
    Write-Host "`n当前默认模型 : " -NoNewline; Write-Host (Get-OCConfig 'agents.defaults.model.primary') -ForegroundColor Green
    Write-Host "当前思考等级 : " -NoNewline; Write-Host (Get-OCConfig 'agents.defaults.thinkingDefault') -ForegroundColor Green
    Write-Host "`n已注册模型（provider=$Provider）:"
    try {
        $models = (Get-OCConfig "models.providers.$Provider.models" | Out-String | ConvertFrom-Json)
        foreach ($m in $models) { Write-Host ("  - {0}/{1}" -f $Provider, $m.id) -ForegroundColor Cyan }
    } catch { Write-Warn2 "无法读取模型列表" }
    return
}

if (-not $Model) { Write-Warn2 "请用 -Model <id> 指定模型，或 -List 查看。"; return }
$modelId = ($Model -replace '^.*/','')
$full    = if ($Model -match '/') { $Model } else { "$Provider/$modelId" }

if ($Register) {
    $models = @(Get-OCConfig "models.providers.$Provider.models" | Out-String | ConvertFrom-Json)
    if ($models.id -notcontains $modelId) {
        Write-Step "登记新模型 $modelId 到 provider=$Provider"
        $new = [pscustomobject]@{ id=$modelId; name=$modelId; reasoning=$true;
            input=@('text','image'); contextWindow=131072; contextTokens=96000; maxTokens=32768 }
        $arr = @($models) + $new
        $patch = @{ models = @{ providers = @{ $Provider = @{ models = $arr } } } } | ConvertTo-Json -Depth 100
        $pf = Join-Path $OC 'logs-register.patch.json'; $patch | Set-Content $pf -Encoding utf8
        & openclaw config patch --file $pf | Out-Null; Remove-Item $pf -ErrorAction SilentlyContinue
    } else { Write-Info "$modelId 已登记，跳过。" }
}

Stop-Gateway
Set-OCConfig 'agents.defaults.model.primary' $full
if ($Thinking) { Set-OCConfig 'agents.defaults.thinkingDefault' $Thinking }
if (-not $NoRestart) { Start-Gateway } else { Write-Info "已跳过重启；下次网关启动生效。" }
Write-Host "`n✅ 默认模型 → $full" -ForegroundColor Green
