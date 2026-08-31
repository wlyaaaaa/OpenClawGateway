<#
.SYNOPSIS  备份 OpenClaw 全部配置与密钥（重装/迁移用）。
.DESCRIPTION
  打包 openclaw.json、auth-profiles.json、config.yml、.env、credentials\ 等到
  时间戳目录；若可用，额外调用原生 `openclaw backup` 生成校验归档。
.EXAMPLE   .\backup-config.ps1
.EXAMPLE   .\backup-config.ps1 -Dest D:\OpenClawBackups
#>
param(
    [string]$Dest = (Join-Path $env:USERPROFILE '.openclaw\secrets-backup'),
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
. (Join-Path $PSScriptRoot '_common.ps1')

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$dir = Join-Path $Dest "full-$stamp-$nonce"
New-Item -ItemType Directory -Force $dir | Out-Null

$items = @('openclaw.json','auth-profiles.json','config.yml','.env','gateway.cmd')
$copied = @()
foreach ($it in $items) {
    $src = Join-Path $OC $it
    if (Test-Path $src) {
        Copy-Item $src $dir -Force
        $copied += $it
        if (-not $Json) { Write-Step "已备份 $it" }
    }
}
$cred = Join-Path $OC 'credentials'
if (Test-Path $cred) {
    Copy-Item $cred (Join-Path $dir 'credentials') -Recurse -Force
    $copied += 'credentials'
    if (-not $Json) { Write-Step "已备份 credentials\" }
}

if ($copied.Count -eq 0) {
    Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    throw "No OpenClaw configuration files found under $OC; refusing to report an empty backup as successful."
}

# 原生归档必须由 OpenClaw 自己校验通过。
$nativeOutput = Join-Path $dir 'openclaw-native-backup.zip'
$nativeRaw = & openclaw backup create --output $nativeOutput --no-include-workspace --verify --json 2>$null | Out-String
if ($LASTEXITCODE -ne 0) { throw 'OpenClaw native backup failed.' }
try { $native = $nativeRaw | ConvertFrom-Json -Depth 20 }
catch { throw 'OpenClaw native backup returned invalid JSON.' }
if ($native.dryRun -eq $true -or $native.verified -ne $true -or
    $native.includeWorkspace -ne $false -or @($native.assets).Count -eq 0 -or
    -not (Test-Path -LiteralPath ([string]$native.archivePath) -PathType Leaf)) {
    throw 'OpenClaw native backup verification failed.'
}
if (-not $Json) { Write-Info "原生 OpenClaw 归档已校验通过" }

if ($Json) {
    [ordered]@{
        schema = 'openclaw_backup_result.v1'
        ok = $true
        backup_path = (Resolve-Path -LiteralPath $dir).Path
        copied_items = @($copied)
        native_backup_verified = $true
        native_archive_path = [string]$native.archivePath
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n✅ 备份完成 → $dir" -ForegroundColor Green
    Write-Warn2 "该目录含明文密钥，请勿提交到任何公开仓库。"
}
