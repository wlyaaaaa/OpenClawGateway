<#
.SYNOPSIS  设置 OpenClaw 默认思考等级与思考显示方式。
.EXAMPLE   .\set-thinking.ps1 -Level max            # 最高思考（最强推理）
.EXAMPLE   .\set-thinking.ps1 -Level off -Reasoning off   # 最省 token
.NOTES     Level: off|minimal|low|medium|high|adaptive|max ；Reasoning: on|off|stream
#>
param(
    [ValidateSet('off','minimal','low','medium','high','adaptive','max')][string]$Level = 'max',
    [ValidateSet('on','off','stream')][string]$Reasoning = 'stream',
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Stop-Gateway
Set-OCConfig 'agents.defaults.thinkingDefault' $Level
Set-OCConfig 'agents.defaults.reasoningDefault' $Reasoning
if (-not $NoRestart) { Start-Gateway }
Write-Host "`n✅ 思考等级 → $Level （显示=$Reasoning）" -ForegroundColor Green
