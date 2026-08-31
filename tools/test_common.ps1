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
    @{ action='restart'; result='restarted'; expected=$true; legacy=$true },
    @{ action='restart'; result='scheduled'; expected=$true },
    @{ action='restart'; result='deferred'; expected=$true },
    @{ action='restart'; result='coalesced'; expected=$true },
    @{ action='restart'; result='accepted'; expected=$false },
    @{ action='restart'; result='arbitrary'; expected=$false }
)
foreach ($case in $cases) {
    $legacy = $case.ContainsKey('legacy') -and [bool]$case.legacy
    $payload = [pscustomobject]@{
        action = $(if($case.action -eq 'restart' -and -not $legacy){$null}else{$case.action})
        ok = $true
        result = $case.result
        error = $null
        restart = $(if($case.action -eq 'restart' -and -not $legacy){
            [pscustomobject]@{ ok=$true; pid=123; signal='SIGUSR1'; reason='gateway.restart.safe' }
        }else{$null})
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
if (Test-OcDaemonAck ([pscustomobject]@{
    ok=$true; result='deferred'; error=$null; restart=$null
}) 'restart') {
    throw 'Incomplete OpenClaw 2.0 restart receipt was accepted.'
}

$script:waitCalled = $false
function Get-OcListenerPids { return @(111) }
function Invoke-OcDaemonAction {
    param([string]$Action)
    $script:OcLastDaemonResult = [pscustomobject]@{ result='deferred' }
    return $true
}
function Wait-OcGateway {
    param([bool]$Running,[int]$TimeoutSec)
    $script:waitCalled = $true
    throw 'Deferred restart must not wait inside the requesting call.'
}
Restart-Gateway
if ($script:waitCalled) { throw 'Deferred restart entered the synchronous wait path.' }

[Console]::WriteLine('PASS official daemon response contracts')
