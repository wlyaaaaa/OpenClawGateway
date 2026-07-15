#Requires -Version 7.0
<#
  Fixture tests for _update_lib.ps1 pure functions (R7).
  Exits non-zero on any assertion failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_update_lib.ps1')

$script:pass = 0
$script:fail = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        $script:pass++
    } else {
        $script:fail++
        [Console]::Error.WriteLine("FAIL: $Label — expected '$Expected', got '$Actual'")
    }
}

# --- Get-OpenClawVersionToken ---
Assert-Equal '2026.7.1' (Get-OpenClawVersionToken 'OpenClaw 2026.7.1 (2d2ddc4)') 'version-token-openclaw'
Assert-Equal '2026.7.1-beta.1' (Get-OpenClawVersionToken '2026.7.1-beta.1') 'version-token-prerelease'
Assert-Equal $null (Get-OpenClawVersionToken '') 'version-token-empty'
Assert-Equal $null (Get-OpenClawVersionToken 'warning only, no version') 'version-token-rejects-arbitrary-text'

# --- ConvertTo-NpmTag ---
Assert-Equal 'latest' (ConvertTo-NpmTag 'stable') 'tag-stable'
Assert-Equal 'beta' (ConvertTo-NpmTag 'beta') 'tag-beta'
Assert-Equal 'dev' (ConvertTo-NpmTag 'dev') 'tag-dev'
Assert-Equal 'latest' (ConvertTo-NpmTag 'unknown') 'tag-default'

# --- Compare-Versions ---
Assert-Equal 0 (Compare-Versions '2026.7.1' '2026.7.1') 'cmp-equal'
Assert-Equal -1 (Compare-Versions '2026.6.8' '2026.7.1') 'cmp-behind'
Assert-Equal 1 (Compare-Versions '2026.7.2' '2026.7.1') 'cmp-ahead'
Assert-Equal -1 (Compare-Versions '2026.7.1-beta.1' '2026.7.1') 'cmp-prerelease-behind'
Assert-Equal 1 (Compare-Versions '2026.7.1' '2026.7.1-beta.1') 'cmp-prerelease-ahead'
Assert-Equal 1 (Compare-Versions '2026.7.1-beta.10' '2026.7.1-beta.2') 'cmp-prerelease-numeric-identifiers'
Assert-Equal -1 (Compare-Versions '2026.7.1-alpha' '2026.7.1-beta') 'cmp-prerelease-lexical-identifiers'
Assert-Equal 0 (Compare-Versions '1.2.3' '1.2.3') 'cmp-semver-equal'
Assert-Equal -1 (Compare-Versions '1.2.2' '1.2.3') 'cmp-semver-behind'
Assert-Equal $null (Compare-Versions 'not-a-version' '1.2.3') 'cmp-invalid-is-null'

# --- Get-VersionRelation (R7 state machine) ---
Assert-Equal 'equal' (Get-VersionRelation '2026.7.1' '2026.7.1' $true $true 'stable' $true) 'rel-equal'
Assert-Equal 'behind' (Get-VersionRelation '2026.6.8' '2026.7.1' $true $true 'stable' $true) 'rel-behind'
Assert-Equal 'ahead' (Get-VersionRelation '2026.7.2' '2026.7.1' $true $true 'stable' $true) 'rel-ahead'
Assert-Equal 'unknown' (Get-VersionRelation '2026.7.1' $null $true $false 'stable' $true) 'rel-target-fail'
Assert-Equal 'unknown' (Get-VersionRelation $null '2026.7.1' $false $true 'stable' $true) 'rel-current-fail'
Assert-Equal 'unknown' (Get-VersionRelation '' '2026.7.1' $true $true 'stable' $true) 'rel-empty-current'
Assert-Equal 'channel_mismatch' (Get-VersionRelation '2026.7.1' '2026.7.1' $true $true 'unknown' $false) 'rel-channel-mismatch'
Assert-Equal 'channel_mismatch' (Get-VersionRelation '2026.7.1' '2026.7.1' $true $true 'stable' $false) 'rel-channel-resolve-fail-no-matter-channel-str'
Assert-Equal 'unknown' (Get-VersionRelation '2026.7.1' $null $true $false 'stable' $true) 'rel-unknown-takes-precedence-over-channel'
Assert-Equal 'unknown' (Get-VersionRelation 'not-a-version' '2026.7.1' $true $true 'stable' $true) 'rel-invalid-version-is-unknown'

# --- Invoke-ExternalLines timeout must be real, not a decorative parameter ---
$slow = Join-Path $env:TEMP "openclaw-update-lib-slow-$PID.ps1"
@'
Start-Sleep -Seconds 3
Write-Output 'finished-too-late'
'@ | Set-Content -LiteralPath $slow -Encoding utf8
$sw = [Diagnostics.Stopwatch]::StartNew()
$timeoutRun = Invoke-ExternalLines -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile', '-File', $slow) -TimeoutSec 1
$sw.Stop()
Assert-Equal $true $timeoutRun.TimedOut 'external-timeout-flag'
Assert-Equal -1 $timeoutRun.ExitCode 'external-timeout-exit'
Assert-Equal $true ($sw.Elapsed.TotalSeconds -lt 2.5) 'external-timeout-is-bounded'
Remove-Item -LiteralPath $slow -Force -ErrorAction SilentlyContinue

# --- ResultPath atomic write supports a new parent and cleans its temp file ---
$resultRoot = Join-Path $env:TEMP "openclaw-json-result-$PID"
Remove-Item -LiteralPath $resultRoot -Recurse -Force -ErrorAction SilentlyContinue
$resultPath = Join-Path $resultRoot 'nested\receipt.json'
Write-JsonResult -Data ([ordered]@{ schema='test.v1'; ok=$true }) -ResultPath $resultPath | Out-Null
Assert-Equal $true (Test-Path -LiteralPath $resultPath) 'result-path-creates-parent'
$partials = @(Get-ChildItem -LiteralPath (Split-Path -Parent $resultPath) -Filter '*.tmp*' -ErrorAction SilentlyContinue)
Assert-Equal 0 $partials.Count 'result-path-leaves-no-partial'
Remove-Item -LiteralPath $resultRoot -Recurse -Force -ErrorAction SilentlyContinue

# --- Test-IsAdmin (should be false in normal agent context) ---
$adminStatus = Test-IsAdmin
Assert-Equal $false $adminStatus 'is-admin-false-in-agent'

[Console]::WriteLine("PASS=$($script:pass) FAIL=$($script:fail)")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
