#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:TEMP ('openclaw-backup-config-test-' + [Guid]::NewGuid().ToString('N'))
$dest = Join-Path $root 'backups'
$fakeBin = Join-Path $root 'bin'
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
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
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath

    $output = & (Join-Path $PSScriptRoot 'backup-config.ps1') -Dest $dest -Json
    $result = $output | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_backup_result.v1' -or $result.ok -ne $true) {
        throw 'Unexpected backup result.'
    }
    if ($result.native_backup_verified -ne $true -or
        -not (Test-Path -LiteralPath $result.backup_path -PathType Leaf)) {
        throw 'Official archive was not verified.'
    }
    if (@(Get-ChildItem -LiteralPath $dest -File).Count -ne 1) {
        throw 'Backup wrapper created files outside the single official archive.'
    }

    $secondOutput = & (Join-Path $PSScriptRoot 'backup-config.ps1') -Dest $dest -Json
    $second = $secondOutput | ConvertFrom-Json
    if ($second.backup_path -eq $result.backup_path) {
        throw 'Back-to-back backups reused an archive path.'
    }
    [Console]::WriteLine('PASS official verified backup wrapper')
}
finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
