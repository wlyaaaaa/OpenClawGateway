<#
.SYNOPSIS  从备份恢复 OpenClaw 配置与密钥。
.EXAMPLE   .\restore-config.ps1 -From "E:\Projects\Tools\OpenClawGateway\secrets-backup\full-20260619-220000"
.EXAMPLE   .\restore-config.ps1 -Latest        # 自动选最新 full-* 备份
.NOTES     恢复前会停网关、并把当前配置另存为 .pre-restore 以便回退。
#>
param(
    [string]$From,
    [switch]$Latest,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

if ($Latest -or -not $From) {
    $From = (Get-ChildItem 'E:\Projects\Tools\OpenClawGateway\secrets-backup' -Directory -Filter 'full-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $From -or -not (Test-Path $From)) { Write-Warn2 "找不到备份目录，请用 -From <路径>。"; return }
Write-Step "从备份恢复：$From"

Stop-Gateway
Get-ChildItem $From -File | ForEach-Object {
    $dst = Join-Path $OC $_.Name
    if (Test-Path $dst) { Copy-Item $dst "$dst.pre-restore" -Force }
    Copy-Item $_.FullName $dst -Force
    Write-Step "已恢复 $($_.Name)"
}
$credBak = Join-Path $From 'credentials'
if (Test-Path $credBak) { Copy-Item $credBak (Join-Path $OC 'credentials') -Recurse -Force; Write-Step "已恢复 credentials\" }

if (-not $NoRestart) { Start-Gateway }
Write-Host "`n✅ 恢复完成。" -ForegroundColor Green
