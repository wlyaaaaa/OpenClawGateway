<#
.SYNOPSIS
  验证 OpenClaw 官方备份，并恢复到全新的暂存目录。
.DESCRIPTION
  OpenClaw 2.0 的恢复合同是 staging-only（只恢复到暂存区）：不会停网关，
  不会覆盖当前配置，也不会自动激活。确认暂存内容后，离线激活应按官方恢复
  指南单独执行。
#>
[CmdletBinding()]
param(
    [string]$From,
    [switch]$Latest,
    [string]$Target,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-OpenClawArchive([string]$InputPath) {
    if ([string]::IsNullOrWhiteSpace($InputPath)) { return $null }
    if (Test-Path -LiteralPath $InputPath -PathType Leaf) {
        return (Resolve-Path -LiteralPath $InputPath).Path
    }
    if (Test-Path -LiteralPath $InputPath -PathType Container) {
        $legacy = Join-Path $InputPath 'openclaw-native-backup.zip'
        if (Test-Path -LiteralPath $legacy -PathType Leaf) {
            return (Resolve-Path -LiteralPath $legacy).Path
        }
        $candidates = @(
            Get-ChildItem -LiteralPath $InputPath -File |
                Where-Object { $_.Name -match '\.(zip|tar\.gz)$' } |
                Sort-Object LastWriteTimeUtc -Descending
        )
        if ($candidates.Count -eq 0) { return $null }
        return $candidates[0].FullName
    }
    return $null
}

if ($Latest -or [string]::IsNullOrWhiteSpace($From)) {
    $backupRoot = if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_BACKUP_DIR)) {
        Join-Path $env:USERPROFILE 'OpenClawBackups'
    }
    else { $env:OPENCLAW_BACKUP_DIR }
    $latestArchive = @(
        Get-ChildItem -LiteralPath $backupRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(zip|tar\.gz)$' } |
            Sort-Object LastWriteTimeUtc -Descending
    ) | Select-Object -First 1
    if ($null -ne $latestArchive) { $From = $latestArchive.FullName }
}

$archive = Resolve-OpenClawArchive $From
if ([string]::IsNullOrWhiteSpace($archive)) {
    throw '找不到 OpenClaw 备份归档；请用 -From 指定归档文件或备份目录。'
}

if ([string]::IsNullOrWhiteSpace($Target)) {
    $parent = Split-Path -Parent $archive
    $Target = Join-Path $parent (
        'restore-stage-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' +
        [Guid]::NewGuid().ToString('N').Substring(0, 8)
    )
}
$targetFull = [IO.Path]::GetFullPath($Target)
if (Test-Path -LiteralPath $targetFull) {
    throw '恢复目标必须是尚不存在的全新目录。'
}

$verifyRaw = & openclaw backup verify $archive --json 2>$null | Out-String
if ($LASTEXITCODE -ne 0) { throw 'OpenClaw official backup verification failed.' }
try { $verify = $verifyRaw | ConvertFrom-Json -Depth 30 }
catch { throw 'OpenClaw official backup verification returned invalid JSON.' }
foreach ($property in @('ok', 'valid', 'verified')) {
    $value = $verify.PSObject.Properties[$property]
    if ($null -ne $value -and $value.Value -ne $true) {
        throw "OpenClaw backup verification reported $property=false."
    }
}

$restoreRaw = & openclaw backup restore $archive --target $targetFull --json 2>$null | Out-String
if ($LASTEXITCODE -ne 0) { throw 'OpenClaw official staged restore failed.' }
try { $restore = $restoreRaw | ConvertFrom-Json -Depth 30 }
catch { throw 'OpenClaw official staged restore returned invalid JSON.' }

$restoredFiles = @(
    Get-ChildItem -LiteralPath $targetFull -File -Recurse -Force -ErrorAction SilentlyContinue
)
if (-not (Test-Path -LiteralPath $targetFull -PathType Container) -or $restoredFiles.Count -eq 0) {
    throw 'OpenClaw staged restore produced no readable files.'
}

$result = [ordered]@{
    schema = 'openclaw_restore_stage_result.v1'
    ok = $true
    archive = $archive
    target = $targetFull
    file_count = $restoredFiles.Count
    verified = $true
    activation_performed = $false
    activation_required = $true
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress
}
else {
    Write-Host "恢复暂存完成：$targetFull" -ForegroundColor Green
    Write-Warning '当前运行配置未被覆盖；检查暂存内容后再离线激活。'
}
