<#
.SYNOPSIS
  创建并验证 OpenClaw 官方备份归档。
.DESCRIPTION
  只调用 `openclaw backup create --verify`。不再自行复制认证文件、SQLite
  或凭据目录，避免两套备份语义漂移。归档包含敏感状态，只能存放在私人位置。
#>
[CmdletBinding()]
param(
    [string]$Dest = $(
        if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_BACKUP_DIR)) {
            Join-Path $env:USERPROFILE 'OpenClawBackups'
        }
        else { $env:OPENCLAW_BACKUP_DIR }
    ),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

New-Item -ItemType Directory -Path $Dest -Force | Out-Null
$resolvedDest = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Dest).Path).TrimEnd('\', '/')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$requestedArchive = Join-Path $resolvedDest "openclaw-$stamp-$nonce.tar.gz"

try {
    $nativeRaw = & openclaw backup create `
        --output $requestedArchive `
        --no-include-workspace `
        --verify `
        --json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'OpenClaw official backup command failed.' }
    try { $native = $nativeRaw | ConvertFrom-Json -Depth 30 }
    catch { throw 'OpenClaw official backup returned invalid JSON.' }

    $archivePath = [IO.Path]::GetFullPath([string]$native.archivePath)
    $insideDest = $archivePath.StartsWith(
        $resolvedDest + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )
    if ($native.dryRun -eq $true -or
        $native.verified -ne $true -or
        $native.includeWorkspace -ne $false -or
        @($native.assets).Count -eq 0 -or
        -not $insideDest -or
        -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw 'OpenClaw official backup verification failed.'
    }

    $result = [ordered]@{
        schema = 'openclaw_backup_result.v1'
        ok = $true
        backup_path = $archivePath
        native_backup_verified = $true
        include_workspace = $false
    }
    if ($Json) {
        $result | ConvertTo-Json -Depth 6 -Compress
    }
    else {
        Write-Host "备份完成并通过官方校验：$archivePath" -ForegroundColor Green
        Write-Warning '该归档含私人配置和凭据，不得提交到公开仓库。'
    }
}
catch {
    if (Test-Path -LiteralPath $requestedArchive -PathType Leaf) {
        Remove-Item -LiteralPath $requestedArchive -Force
    }
    throw
}
