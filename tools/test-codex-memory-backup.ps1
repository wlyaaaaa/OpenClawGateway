param()

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'backup-codex-memory.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing backup script: $script"
}

function New-TestFile {
    param(
        [string]$Path,
        [string]$Content = 'fixture'
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Assert-Any([string[]]$Files, [string]$Pattern, [string]$Message) {
    if (@($Files | Where-Object { $_ -like $Pattern }).Count -eq 0) {
        throw $Message
    }
}

function Assert-None([string[]]$Files, [string]$Regex, [string]$Message) {
    $matches = @($Files | Where-Object { $_ -match $Regex })
    if ($matches.Count -gt 0) {
        throw "$Message Example: $($matches[0])"
    }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'openclaw-codex-memory-backup-{0}-{1}' -f $PID, [Guid]::NewGuid().ToString('N')
)
$previousSettings = $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $sourceRoot = Join-Path $testRoot 'source'
    $snapshotRoot = Join-Path $testRoot 'snapshot'
    $cloudRepo = Join-Path $testRoot 'cloud-repo'
    $logFile = Join-Path $testRoot 'logs\backup.log'
    $settingsPath = Join-Path $testRoot 'private-backup.local.json'
    $manifest = Join-Path $testRoot 'manifest.json'

    foreach ($path in @(
        'AGENTS.md',
        'config.toml',
        'version.json',
        'chrome-native-hosts-v2.json',
        'browser\config.toml',
        'computer-use\config.json',
        'vendor_imports\skills-curated-cache.json',
        'memories\raw_memories.md',
        'memories\extensions\ad_hoc\instructions.md',
        'skills\.system\fixture\SKILL.md',
        '.git\config',
        'sessions\ignored.jsonl'
    )) {
        New-TestFile (Join-Path $sourceRoot $path)
    }

    [ordered]@{
        schema = 'openclaw_gateway.private_backup_settings.v1'
        codex_memory = [ordered]@{
            source_root = $sourceRoot
            snapshot_root = $snapshotRoot
            cloud_repo = $cloudRepo
            log_file = $logFile
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsPath -Encoding utf8

    $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS = $settingsPath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -DryRun -ManifestPath $manifest
    if ($LASTEXITCODE -ne 0) {
        throw "Dry-run failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "Dry-run did not create manifest: $manifest"
    }
    if (Test-Path -LiteralPath $snapshotRoot) {
        throw 'Dry-run must not create a local snapshot directory.'
    }
    if (Test-Path -LiteralPath $cloudRepo) {
        throw 'Dry-run must not access or create the cloud backup repository.'
    }

    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $files = @($data.files | ForEach-Object { [string]$_ })

    Assert-Any $files 'AGENTS.md' 'AGENTS.md must be backed up.'
    Assert-Any $files 'config.toml' 'config.toml must be backed up.'
    Assert-Any $files 'version.json' 'version.json must be backed up.'
    Assert-Any $files 'chrome-native-hosts-v2.json' 'Native host config must be backed up.'
    Assert-Any $files 'browser/config.toml' 'Browser config must be backed up.'
    Assert-Any $files 'computer-use/config.json' 'Computer-use config must be backed up.'
    Assert-Any $files 'memories/raw_memories.md' 'Codex raw memories must be backed up.'
    Assert-Any $files 'memories/extensions/ad_hoc/instructions.md' 'Codex ad hoc instructions must be backed up.'
    Assert-Any $files 'skills/.system/*/SKILL.md' 'Installed Codex skills must be backed up.'
    Assert-Any $files 'vendor_imports/skills-curated-cache.json' 'Curated skill cache metadata must be backed up.'

    Assert-None $files '^auth\.json$' 'Auth file must not be backed up.'
    Assert-None $files '^installation_id$' 'Installation id must not be backed up.'
    Assert-None $files '^\.codex-global-state\.json' 'Global runtime state must not be backed up.'
    Assert-None $files '^claude-cowork-' 'Imported transcript state must not be backed up.'
    Assert-None $files '^external_agent_session_imports\.json$' 'External agent import state must not be backed up.'
    Assert-None $files '^session_index\.jsonl$' 'Session index must not be backed up.'
    Assert-None $files '^models_cache\.json$' 'Model cache must not be backed up.'
    Assert-None $files '(^|/)\.git(/|$)' 'Nested git metadata must not be backed up.'
    Assert-None $files '^(sessions|plugins|packages|cache|tmp|\.tmp|sqlite|process_manager|pets)/' 'Runtime/cache directories must not be backed up.'
    Assert-None $files '\.(sqlite|sqlite3|db|db-shm|db-wal|jsonl)$' 'Databases and JSONL transcripts must not be backed up.'

    if ($files.Count -lt 10) {
        throw "Dry-run selected too few files: $($files.Count)"
    }
    if ([double]$data.totalSizeBytes -gt 5MB) {
        throw "Dry-run selected too much data: $($data.totalSizeBytes) bytes"
    }

    Write-Host "OK Codex memory backup dry-run manifest is safe ($($files.Count) files, $($data.totalSizeBytes) bytes)"
} finally {
    if ($null -eq $previousSettings) {
        Remove-Item -Path Env:OPENCLAW_PRIVATE_BACKUP_SETTINGS -ErrorAction SilentlyContinue
    } else {
        $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS = $previousSettings
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
