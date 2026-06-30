param()

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'backup-codex-memory.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing backup script: $script"
}

$manifest = Join-Path $env:TEMP ("codex-memory-backup-manifest-{0}.json" -f $PID)
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

Assert-Any 'AGENTS.md' 'AGENTS.md must be backed up'
Assert-Any 'config.toml' 'config.toml must be backed up'
Assert-Any 'version.json' 'version.json must be backed up'
Assert-Any 'chrome-native-hosts-v2.json' 'native host config must be backed up'
Assert-Any 'browser/config.toml' 'browser config must be backed up'
Assert-Any 'computer-use/config.json' 'computer-use config must be backed up'
Assert-Any 'memories/raw_memories.md' 'Codex raw memories must be backed up'
Assert-Any 'memories/extensions/ad_hoc/instructions.md' 'Codex ad hoc memory instructions must be backed up'
Assert-Any 'skills/.system/*/SKILL.md' 'Installed Codex skill definitions must be backed up'
Assert-Any 'vendor_imports/skills-curated-cache.json' 'Skill curated cache metadata must be backed up'

Assert-None '^auth\.json$' 'Auth file must not be backed up.'
Assert-None '^installation_id$' 'Installation id must not be backed up.'
Assert-None '^\.codex-global-state\.json' 'Global runtime state must not be backed up.'
Assert-None '^claude-cowork-' 'Imported transcript state must not be backed up.'
Assert-None '^external_agent_session_imports\.json$' 'External agent import state must not be backed up.'
Assert-None '^session_index\.jsonl$' 'Session index must not be backed up.'
Assert-None '^models_cache\.json$' 'Model cache must not be backed up.'
Assert-None '(^|/)\.git(/|$)' 'Nested git metadata must not be backed up.'
Assert-None '^(sessions|plugins|packages|cache|tmp|\.tmp|sqlite|process_manager|pets)/' 'Runtime/cache directories must not be backed up.'
Assert-None '\.(sqlite|sqlite3|db|db-shm|db-wal|jsonl)$' 'Databases and JSONL transcripts must not be backed up.'

if ($files.Count -lt 10) {
    throw "Dry-run selected too few files: $($files.Count)"
}
if ([double]$data.totalSizeBytes -gt 5MB) {
    throw "Dry-run selected too much data: $($data.totalSizeBytes) bytes"
}

Remove-Item -LiteralPath $manifest -Force
Write-Host "OK Codex memory backup dry-run manifest is safe ($($files.Count) files, $($data.totalSizeBytes) bytes)"
