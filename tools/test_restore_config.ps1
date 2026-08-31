#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'openclaw-restore-exact-' + [Guid]::NewGuid().ToString('N')
)
try {
    $source = Join-Path $root 'backup\credentials'
    $target = Join-Path $root 'profile\credentials'
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $source 'new.json'), '{"fixture":"new"}',
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $source 'nested\item.txt'), 'new nested',
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $target 'old.json'), '{"fixture":"old"}',
        [Text.UTF8Encoding]::new($false)
    )

    . (Join-Path $PSScriptRoot 'restore-config.ps1')
    $rollback = Copy-OcDirectoryExact $source $target

    if (-not (Test-Path (Join-Path $target 'new.json')) -or
        -not (Test-Path (Join-Path $target 'nested\item.txt')) -or
        (Test-Path (Join-Path $target 'old.json')) -or
        (Test-Path (Join-Path $target 'credentials'))) {
        throw 'Exact credentials replacement failed.'
    }
    if (-not (Test-Path (Join-Path $rollback 'old.json'))) {
        throw 'Previous credentials were not preserved.'
    }
    if (((Get-OcDirectoryInventory $source) | ConvertTo-Json -Compress) -cne
        ((Get-OcDirectoryInventory $target) | ConvertTo-Json -Compress)) {
        throw 'Restored credentials do not match the backup.'
    }
    Write-Output 'PASS exact credentials replacement and rollback preservation'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
