$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host "Stopping OpenClaw Gateway..."
Stop-Gateway

try {
    Write-Host "Running python script to update configuration files..."
    python (Join-Path $PSScriptRoot "register_deepseek.py")
} finally {
    Write-Host "Starting OpenClaw Gateway..."
    Start-Gateway
}

Write-Host "Successfully completed model update and restarted gateway."
