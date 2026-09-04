#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$statusScript = Join-Path $PSScriptRoot 'status.ps1'
$tempRoot = Join-Path $env:TEMP ('openclaw-status-test-' + [Guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $fake = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
exit 7
'@
    [IO.File]::WriteAllText((Join-Path $tempRoot 'openclaw.ps1'), $fake, [Text.UTF8Encoding]::new($false))
    $env:PATH = $tempRoot + [IO.Path]::PathSeparator + $oldPath
    $null = & pwsh -NoLogo -NoProfile -NonInteractive -File $statusScript 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw 'Status panel returned success while all OpenClaw probes failed.'
    }
    [Console]::WriteLine('PASS status panel propagates critical probe failure')
}
finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
