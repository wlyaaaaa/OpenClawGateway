<#
.SYNOPSIS  备份 OpenClaw 全部配置与密钥（重装/迁移用）。
.DESCRIPTION
  打包 openclaw.json、auth-profiles.json、config.yml、.env、credentials\ 等到
  时间戳目录；若可用，额外调用原生 `openclaw backup` 生成校验归档。
.EXAMPLE   .\backup-config.ps1
.EXAMPLE   .\backup-config.ps1 -Dest D:\OpenClawBackups
#>
param(
    [string]$Dest = 'E:\OpenClawGateway\secrets-backup'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = Join-Path $Dest "full-$stamp"
New-Item -ItemType Directory -Force $dir | Out-Null

$items = @('openclaw.json','auth-profiles.json','config.yml','.env','gateway.cmd')
foreach ($it in $items) {
    $src = Join-Path $OC $it
    if (Test-Path $src) { Copy-Item $src $dir -Force; Write-Step "已备份 $it" }
}
$cred = Join-Path $OC 'credentials'
if (Test-Path $cred) { Copy-Item $cred (Join-Path $dir 'credentials') -Recurse -Force; Write-Step "已备份 credentials\" }

# 原生归档（best-effort）
try {
    & openclaw backup create --out (Join-Path $dir 'openclaw-native-backup') 2>$null | Out-Null
    Write-Info "原生 openclaw backup 已尝试生成"
} catch { Write-Info "原生 backup 不可用，跳过（文件级备份已完成）" }

Write-Host "`n✅ 备份完成 → $dir" -ForegroundColor Green
Write-Warn2 "该目录含明文密钥，请勿提交到任何仓库（已被 .gitignore 排除）。"
