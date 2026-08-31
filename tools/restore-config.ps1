<#
.SYNOPSIS  从备份恢复 OpenClaw 配置与密钥。
.EXAMPLE   .\restore-config.ps1 -From "$env:USERPROFILE\.openclaw\secrets-backup\full-20260619-220000"
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

function Get-OcDirectoryInventory {
    param([string]$Root)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return @(
        Get-ChildItem -LiteralPath $base -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject]@{
                    path = [IO.Path]::GetRelativePath($base, $_.FullName).Replace('\', '/')
                    length = [int64]$_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            }
    )
}

function Copy-OcDirectoryExact {
    param([string]$Source, [string]$Target)
    $sourceInventory = @(Get-OcDirectoryInventory $Source)
    if ($sourceInventory.Count -eq 0) { throw 'Credentials backup is empty.' }
    $parent = Split-Path -Parent $Target
    $nonce = [Guid]::NewGuid().ToString('N')
    $candidate = Join-Path $parent ".credentials-candidate-$nonce"
    $rollback = Join-Path $parent "credentials.pre-restore-$nonce"
    $failed = Join-Path $parent ".credentials-failed-$nonce"
    $oldMoved = $false
    $newActivated = $false
    try {
        New-Item -ItemType Directory -Path $candidate | Out-Null
        Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $candidate -Recurse -Force
        }
        if (((Get-OcDirectoryInventory $candidate) | ConvertTo-Json -Compress) -cne
            ($sourceInventory | ConvertTo-Json -Compress)) {
            throw 'Credentials staging readback failed.'
        }
        if (Test-Path -LiteralPath $Target) {
            Move-Item -LiteralPath $Target -Destination $rollback
            $oldMoved = $true
        }
        Move-Item -LiteralPath $candidate -Destination $Target
        $newActivated = $true
        if (((Get-OcDirectoryInventory $Target) | ConvertTo-Json -Compress) -cne
            ($sourceInventory | ConvertTo-Json -Compress)) {
            throw 'Credentials restore readback failed.'
        }
        return $rollback
    }
    catch {
        if ($newActivated -and (Test-Path -LiteralPath $Target)) {
            Move-Item -LiteralPath $Target -Destination $failed
        }
        if ($oldMoved -and (Test-Path -LiteralPath $rollback)) {
            Move-Item -LiteralPath $rollback -Destination $Target
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $candidate) {
            Remove-Item -LiteralPath $candidate -Recurse -Force
        }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

if ($Latest -or -not $From) {
    $privateBackupRoot = Join-Path $env:USERPROFILE '.openclaw\secrets-backup'
    $From = (Get-ChildItem $privateBackupRoot -Directory -Filter 'full-*' -ErrorAction SilentlyContinue |
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
if (Test-Path $credBak) {
    $rollback = Copy-OcDirectoryExact $credBak (Join-Path $OC 'credentials')
    Write-Step "已精确恢复 credentials\"
    if (Test-Path -LiteralPath $rollback) { Write-Info "原 credentials\ 已保留用于回退。" }
}

if (-not $NoRestart) { Start-Gateway }
Write-Host "`n✅ 恢复完成。" -ForegroundColor Green
