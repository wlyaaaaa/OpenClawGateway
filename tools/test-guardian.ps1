#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'openclaw_silent_boot_guardian.ps1'
$tempRoot = Join-Path $env:TEMP ('openclaw-guardian-test-' + [Guid]::NewGuid().ToString('N'))
$fakeBin = Join-Path $tempRoot 'bin'
$marker = Join-Path $tempRoot 'repair-called.txt'
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    $fake = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
if ($Arguments[0] -eq 'gateway' -and $Arguments[1] -eq 'status') {
    [ordered]@{ rpc=[ordered]@{ ok=$true; version='fixture' } } | ConvertTo-Json -Depth 4
    exit 0
}
if ($Arguments[0] -eq 'gateway' -and $Arguments[1] -eq 'install') {
    [IO.File]::WriteAllText($env:OPENCLAW_GUARDIAN_REPAIR_MARKER, 'called')
    [ordered]@{ ok=$true } | ConvertTo-Json
    exit 0
}
exit 3
'@
    [IO.File]::WriteAllText(
        (Join-Path $fakeBin 'openclaw.ps1'),
        $fake,
        [Text.UTF8Encoding]::new($false)
    )
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath
    $env:OPENCLAW_GUARDIAN_REPAIR_MARKER = $marker

    function global:Get-ScheduledTask {
        [pscustomobject]@{
            State = 'Running'
            Settings = [pscustomobject]@{ Hidden = $true }
            Principal = [pscustomobject]@{ RunLevel='Highest'; LogonType='S4U' }
            Triggers = @([pscustomobject]@{ CimClass=[pscustomobject]@{ CimClassName='MSFT_TaskBootTrigger' } })
            Actions = @([pscustomobject]@{ Execute='fixture.exe'; Arguments='' })
        }
    }

    $raw = & $scriptPath `
        -Json `
        -PcConfigRoot (Join-Path $tempRoot 'missing-pcconfig') `
        -ManagedLauncher (Join-Path $tempRoot 'missing-launcher.ps1') `
        -PwshPath (Join-Path $tempRoot 'missing-pwsh.exe')
    $result = $raw | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_gateway.windows_residency.v1' -or
        $result.healthy -ne $true -or
        $result.repair_requested -ne $false -or
        $result.repair_route -ne 'none') {
        throw 'Unexpected read-only guardian result.'
    }
    if (Test-Path -LiteralPath $marker) {
        throw 'Default guardian path invoked repair.'
    }

    [Console]::WriteLine('PASS guardian default path is read-only and RPC-backed')
}
finally {
    Remove-Item Function:\Get-ScheduledTask -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCLAW_GUARDIAN_REPAIR_MARKER -ErrorAction SilentlyContinue
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
