param()

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'backup-gemini-memory.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing backup script: $script"
}

$manifest = Join-Path $env:TEMP ("gemini-memory-backup-manifest-{0}.json" -f $PID)
if (Test-Path -LiteralPath $manifest) {
    Remove-Item -LiteralPath $manifest -Force
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -DryRun -ManifestPath $manifest
if ($LASTEXITCODE -ne 0) {
    throw "Dry-run failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Dry-run did not create manifest: $manifest"
}

$data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$files = @($data.files | ForEach-Object { [string]$_ })

function Assert-Any([string]$pattern, [string]$message) {
    $matches = @($files | Where-Object { $_ -like $pattern })
    if ($matches.Count -eq 0) {
        throw $message
    }
}

function Assert-None([string]$regex, [string]$message) {
    $matches = @($files | Where-Object { $_ -match $regex })
    if ($matches.Count -gt 0) {
        throw "$message Example: $($matches[0])"
    }
}

Assert-Any 'projects.json' 'projects.json must be backed up'
Assert-Any 'config/config.json' 'config/config.json must be backed up'
Assert-Any 'config/projects/*.json' 'project config JSON files must be backed up'
Assert-Any 'config/plugins/google-antigravity-sdk/plugin.json' 'Antigravity plugin config must be backed up'
Assert-Any 'antigravity/antigravity_state.pbtxt' 'Antigravity state pbtxt must be backed up'
Assert-Any 'antigravity/annotations/*.pbtxt' 'Antigravity annotation pbtxt files must be backed up'
Assert-Any 'antigravity/brain/*/walkthrough.md' 'Readable brain walkthrough markdown must be backed up'
Assert-Any 'antigravity/brain/*/*.metadata.json' 'Readable brain metadata JSON must be backed up'

Assert-None '\\.system_generated/' 'Generated transcripts/messages must not be backed up.'
Assert-None '/scratch/' 'Scratch files must not be backed up.'
Assert-None '^antigravity/conversations/' 'Conversation databases must not be backed up.'
Assert-None '^tmp/' 'Temporary files must not be backed up.'
Assert-None '^history/' 'History files must not be backed up.'
Assert-None '\.(db|sqlite|sqlite3|mp4|webm|png|jpg|jpeg|pdf|exe|pb)$' 'Binary/media/database files must not be backed up.'

if ($files.Count -lt 20) {
    throw "Dry-run selected too few files: $($files.Count)"
}
if ([double]$data.totalSizeBytes -gt 10MB) {
    throw "Dry-run selected too much data: $($data.totalSizeBytes) bytes"
}

Remove-Item -LiteralPath $manifest -Force
Write-Host "OK Gemini memory backup dry-run manifest is safe ($($files.Count) files, $($data.totalSizeBytes) bytes)"
