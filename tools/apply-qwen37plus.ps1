$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host "Stopping OpenClaw Gateway..."
Stop-Gateway

try {
    Write-Host "Running python script to update configuration files..."
    python (Join-Path $PSScriptRoot "register_qwen37plus.py")
    
    # Session clearing with safety backup
    $sessionDir = Join-Path $OC 'agents\main\sessions'
    if (Test-Path $sessionDir) {
        $timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
        $backupDir = Join-Path $OC "session-backup-$timestamp"
        Write-Host "Archiving existing sessions to $backupDir..."
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        # Move all files from sessions folder to backup
        Get-ChildItem -Path $sessionDir -File | ForEach-Object {
            Move-Item -Path $_.FullName -Destination $backupDir -Force
        }
        Write-Host "Sessions cleared and archived successfully."
    } else {
        Write-Host "No sessions directory found, skipping clear."
    }
} finally {
    Write-Host "Starting OpenClaw Gateway..."
    Start-Gateway
}

Write-Host "Successfully completed model update, cleared sessions, and restarted gateway."
