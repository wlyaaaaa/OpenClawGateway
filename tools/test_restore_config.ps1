#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:TEMP ('openclaw-restore-stage-test-' + [Guid]::NewGuid().ToString('N'))
$fakeBin = Join-Path $root 'bin'
$archive = Join-Path $root 'fixture.zip'
$target = Join-Path $root 'stage'
$failedTarget = Join-Path $root 'failed-stage'
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    [IO.File]::WriteAllText($archive, 'fixture archive', [Text.UTF8Encoding]::new($false))
    $fakeOpenClaw = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
if ($Arguments[0] -ne 'backup') { exit 2 }
if ($Arguments[1] -eq 'verify') {
    if ($env:FAKE_OPENCLAW_VERIFY_FAIL -eq '1') { exit 5 }
    [ordered]@{ ok=$true; verified=$true } | ConvertTo-Json
    exit 0
}
if ($Arguments[1] -eq 'restore') {
    $index = [Array]::IndexOf($Arguments, '--target')
    if ($index -lt 0) { exit 3 }
    $target = $Arguments[$index + 1]
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $target 'manifest.json'),
        '{"fixture":true}',
        [Text.UTF8Encoding]::new($false)
    )
    [ordered]@{ ok=$true; targetPath=$target } | ConvertTo-Json
    exit 0
}
exit 4
'@
    [IO.File]::WriteAllText(
        (Join-Path $fakeBin 'openclaw.ps1'),
        $fakeOpenClaw,
        [Text.UTF8Encoding]::new($false)
    )
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath

    $raw = & (Join-Path $PSScriptRoot 'restore-config.ps1') -From $archive -Target $target -Json
    $result = $raw | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_restore_stage_result.v1' -or $result.ok -ne $true) {
        throw 'Unexpected staged restore result.'
    }
    if ($result.activation_performed -ne $false -or $result.activation_required -ne $true) {
        throw 'Staged restore falsely claimed live activation.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'manifest.json') -PathType Leaf)) {
        throw 'Staged restore output was not created.'
    }

    $env:FAKE_OPENCLAW_VERIFY_FAIL = '1'
    $failed = $false
    try {
        $null = & (Join-Path $PSScriptRoot 'restore-config.ps1') -From $archive -Target $failedTarget -Json
    }
    catch { $failed = $true }
    finally { Remove-Item Env:FAKE_OPENCLAW_VERIFY_FAIL -ErrorAction SilentlyContinue }
    if (-not $failed -or (Test-Path -LiteralPath $failedTarget)) {
        throw 'Failed verification modified the restore target.'
    }

    [Console]::WriteLine('PASS official staged restore never overwrites live state')
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:FAKE_OPENCLAW_VERIFY_FAIL -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
