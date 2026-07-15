#Requires -Version 7.0
<# Fixture test for backup-config.ps1 -Json. Uses an isolated fake USERPROFILE. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:TEMP "openclaw-backup-config-test-$PID"
$fakeProfile = Join-Path $root 'profile'
$fakeConfig = Join-Path $fakeProfile '.openclaw'
$dest = Join-Path $root 'backups'
$oldProfile = $env:USERPROFILE
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fakeConfig -Force | Out-Null
    '{"fixture":true}' | Set-Content -LiteralPath (Join-Path $fakeConfig 'openclaw.json') -Encoding utf8
    $env:USERPROFILE = $fakeProfile
    # Prevent the optional native `openclaw backup` call from reading real state.
    $env:PATH = ''

    $output = & (Join-Path $PSScriptRoot 'backup-config.ps1') -Dest $dest -Json
    $result = $output | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_backup_result.v1') { throw "unexpected schema: $($result.schema)" }
    if ($result.ok -ne $true) { throw 'backup result was not ok' }
    if (-not (Test-Path -LiteralPath $result.backup_path)) { throw 'reported backup_path does not exist' }
    if (-not (Test-Path -LiteralPath (Join-Path $result.backup_path 'openclaw.json'))) { throw 'openclaw.json was not copied' }
    $secondOutput = & (Join-Path $PSScriptRoot 'backup-config.ps1') -Dest $dest -Json
    $second = $secondOutput | ConvertFrom-Json
    if ($second.backup_path -eq $result.backup_path) { throw 'back-to-back backups reused the same rollback directory' }
    [Console]::WriteLine('PASS backup-config JSON fixture')
}
finally {
    $env:USERPROFILE = $oldProfile
    $env:PATH = $oldPath
    $resolvedRoot = [IO.Path]::GetFullPath($root)
    $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP)
    if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
