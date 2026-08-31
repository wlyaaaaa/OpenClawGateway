#Requires -Version 7.0
<# Fixture test for backup-config.ps1 -Json. Uses an isolated fake USERPROFILE. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:TEMP "openclaw-backup-config-test-$PID"
$fakeProfile = Join-Path $root 'profile'
$fakeConfig = Join-Path $fakeProfile '.openclaw'
$dest = Join-Path $root 'backups'
$fakeBin = Join-Path $root 'bin'
$oldProfile = $env:USERPROFILE
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fakeConfig -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    '{"fixture":true}' | Set-Content -LiteralPath (Join-Path $fakeConfig 'openclaw.json') -Encoding utf8
    $fakeOpenClaw = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$index = [Array]::IndexOf($Arguments, '--output')
if ($index -lt 0) { exit 2 }
$archive = $Arguments[$index + 1]
[IO.File]::WriteAllText($archive, 'fixture archive', [Text.UTF8Encoding]::new($false))
[ordered]@{
    dryRun = $false
    verified = $true
    includeWorkspace = $false
    assets = @([ordered]@{ kind = 'state' })
    archivePath = $archive
} | ConvertTo-Json -Depth 5
exit 0
'@
    [IO.File]::WriteAllText(
        (Join-Path $fakeBin 'openclaw.ps1'),
        $fakeOpenClaw,
        [Text.UTF8Encoding]::new($false)
    )
    $env:USERPROFILE = $fakeProfile
    # Route the native backup command to an isolated fixture implementation.
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath

    $output = & (Join-Path $PSScriptRoot 'backup-config.ps1') -Dest $dest -Json
    $result = $output | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_backup_result.v1') { throw "unexpected schema: $($result.schema)" }
    if ($result.ok -ne $true) { throw 'backup result was not ok' }
    if (-not (Test-Path -LiteralPath $result.backup_path)) { throw 'reported backup_path does not exist' }
    if (-not (Test-Path -LiteralPath (Join-Path $result.backup_path 'openclaw.json'))) { throw 'openclaw.json was not copied' }
    if ($result.native_backup_verified -ne $true -or
        -not (Test-Path -LiteralPath $result.native_archive_path -PathType Leaf)) {
        throw 'native backup was not verified'
    }
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
