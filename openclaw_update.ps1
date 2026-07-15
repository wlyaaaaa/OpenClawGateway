# =====================================================================
#  OpenClaw Gateway Manual Update Helper
#  Thin human-facing wrapper around tools\managed-component.ps1.
#  The adapter is the single implementation of backup -> update -> wait
#  -> verify, so manual and AI-routed updates cannot drift.
# =====================================================================
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $root) { $root = 'E:\Projects\Tools\OpenClawGateway' }
$adapter = Join-Path $root 'tools\managed-component.ps1'
$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'openclaw_update.log'

function Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $line
}

if (-not (Test-Path -LiteralPath $adapter)) {
    Log "[ERROR] managed update adapter not found: $adapter"
    exit 1
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Log '[ERROR] Must run as Administrator.'
    exit 1
}

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwsh) {
    Log '[ERROR] PowerShell 7 (pwsh.exe) is required.'
    exit 1
}

Log '=== OpenClaw managed update - start ==='
& $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $adapter -Update -Json
$code = $LASTEXITCODE
if ($code -eq 0) {
    Log '[OK] managed update completed successfully.'
} else {
    Log "[ERROR] managed update adapter failed (exit $code). See the JSON receipt above."
}
Log '=== done ==='
exit $code
