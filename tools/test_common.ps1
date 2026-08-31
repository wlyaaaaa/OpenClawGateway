#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$cases = @(
    @{ action='stop'; result='stopped'; expected=$true },
    @{ action='stop'; result='not-loaded'; expected=$false },
    @{ action='start'; result='started'; expected=$true },
    @{ action='start'; result='scheduled'; expected=$true },
    @{ action='start'; result='not-loaded'; expected=$false },
    @{ action='restart'; result='restarted'; expected=$true },
    @{ action='restart'; result='arbitrary'; expected=$false }
)
foreach ($case in $cases) {
    $payload = [pscustomobject]@{
        action = $case.action
        ok = $true
        result = $case.result
        error = $null
    }
    if ((Test-OcDaemonAck $payload $case.action) -ne $case.expected) {
        throw "Unexpected daemon acknowledgement: $($case.action)/$($case.result)"
    }
}
if (Test-OcDaemonAck ([pscustomobject]@{
    action='stop'; ok=$false; result='stopped'; error='fixture'
}) 'stop') {
    throw 'Failed daemon response was accepted.'
}

[Console]::WriteLine('PASS official daemon response contracts')
