<#
.SYNOPSIS  Switch OpenClaw default model (optionally set thinking level).
.EXAMPLE   .\switch-model.ps1 -List
.EXAMPLE   .\switch-model.ps1 -Model qwen3.7-max-2026-05-17 -Thinking max
.EXAMPLE   .\switch-model.ps1 -Model qwen4-max-2026-12-01 -Register
.NOTES     Register new models to provider on first use using -Register parameter.
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
    Write-Host "`nCurrent primary model : " -NoNewline; Write-Host (Get-OCConfig 'agents.defaults.model.primary') -ForegroundColor Green
    Write-Host "Current thinking level : " -NoNewline; Write-Host (Get-OCConfig 'agents.defaults.thinkingDefault') -ForegroundColor Green
    Write-Host "`nRegistered models (provider=$Provider):"
    try {
        $models = (Get-OCConfig "models.providers.$Provider.models" | Out-String | ConvertFrom-Json)
        foreach ($m in $models) { Write-Host ("  - {0}/{1}" -f $Provider, $m.id) -ForegroundColor Cyan }
    } catch { Write-Warn2 "Failed to read models list." }
    return
}

if (-not $Model) { Write-Warn2 "Please specify a model with -Model <id>, or use -List to view."; return }
$modelId = ($Model -replace '^.*/','')
$full    = if ($Model -match '/') { $Model } else { "$Provider/$modelId" }

if ($Register) {
    $parsed = Get-OCConfig "models.providers.$Provider.models" | Out-String | ConvertFrom-Json
    $models = @()
    if ($parsed -is [array]) { $models = $parsed } elseif ($parsed -ne $null) { $models = @($parsed) }
    if ($models.id -notcontains $modelId) {
        Write-Step "Registering new model $modelId to provider=$Provider"
        $new = [pscustomobject]@{ id=$modelId; name=$modelId; reasoning=$true;
            input=@('text','image'); contextWindow=131072; contextTokens=96000; maxTokens=32768 }
        $arr = $models + $new
        $patch = @{ models = @{ providers = @{ $Provider = @{ models = $arr } } } } | ConvertTo-Json -Depth 100
        $pf = Join-Path $OC 'logs-register.patch.json'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($pf, $patch, $utf8NoBom)
        & openclaw config patch --file $pf | Out-Null; Remove-Item $pf -ErrorAction SilentlyContinue
    } else { Write-Info "$modelId already registered, skipping." }
}

Stop-Gateway
Set-OCConfig 'agents.defaults.model.primary' $full
if ($Thinking) { Set-OCConfig 'agents.defaults.thinkingDefault' $Thinking }
if (-not $NoRestart) { Start-Gateway } else { Write-Info "Skipped gateway restart; changes take effect next boot." }
Write-Host "`nDefault model set to -> $full" -ForegroundColor Green
