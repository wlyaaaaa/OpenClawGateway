param()

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'backup-gemini-memory.ps1'
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
    'openclaw-gemini-memory-backup-{0}-{1}' -f $PID, [Guid]::NewGuid().ToString('N')
)
$previousSettings = $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $sourceRoot = Join-Path $testRoot 'source'
    $snapshotRoot = Join-Path $testRoot 'snapshot'
    $hotSnapshotRoot = Join-Path $testRoot 'hot-snapshot'
    $cloudRepo = Join-Path $testRoot 'cloud-repo'
    $logFile = Join-Path $testRoot 'logs\backup.log'
    $settingsPath = Join-Path $testRoot 'private-backup.local.json'
    $manifest = Join-Path $testRoot 'manifest.json'

    foreach ($path in @(
        'projects.json',
        'config\config.json',
        'config\settings.json',
        'config\projects\one.json',
        'config\projects\two.json',
        'config\projects\three.json',
        'config\projects\four.json',
        'config\projects\five.json',
        'config\projects\six.json',
        'config\plugins\google-antigravity-sdk\plugin.json',
        'antigravity\antigravity_state.pbtxt',
        'antigravity\annotations\one.pbtxt',
        'antigravity\annotations\two.pbtxt',
        'antigravity\annotations\three.pbtxt',
        'antigravity\brain\project-one\walkthrough.md',
        'antigravity\brain\project-one\notes.md',
        'antigravity\brain\project-one\one.metadata.json',
        'antigravity\brain\project-one\two.metadata.json',
        'antigravity\brain\project-two\walkthrough.md',
        'antigravity\brain\project-two\notes.md',
        'antigravity\brain\project-two\one.metadata.json',
        'antigravity\brain\project-two\two.metadata.json',
        'antigravity\brain\project-two\scratch\ignored.md',
        'antigravity\brain\project-two\.system_generated\ignored.md',
        'antigravity\conversations\conversation.db',
        'tmp\ignored.txt',
        'history\ignored.txt'
    )) {
        New-TestFile (Join-Path $sourceRoot $path)
    }

    [ordered]@{
        schema = 'openclaw_gateway.private_backup_settings.v1'
        gemini_memory = [ordered]@{
            source_root = $sourceRoot
            snapshot_root = $snapshotRoot
            hot_snapshot_root = $hotSnapshotRoot
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
    foreach ($path in @($snapshotRoot, $hotSnapshotRoot, $cloudRepo)) {
        if (Test-Path -LiteralPath $path) {
            throw 'Dry-run must not create or access a backup destination.'
        }
    }

    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $files = @($data.files | ForEach-Object { [string]$_ })

    Assert-Any $files 'projects.json' 'projects.json must be backed up.'
    Assert-Any $files 'config/config.json' 'config/config.json must be backed up.'
    Assert-Any $files 'config/projects/*.json' 'Project config JSON files must be backed up.'
    Assert-Any $files 'config/plugins/google-antigravity-sdk/plugin.json' 'Antigravity plugin config must be backed up.'
    Assert-Any $files 'antigravity/antigravity_state.pbtxt' 'Antigravity state pbtxt must be backed up.'
    Assert-Any $files 'antigravity/annotations/*.pbtxt' 'Antigravity annotation pbtxt files must be backed up.'
    Assert-Any $files 'antigravity/brain/*/walkthrough.md' 'Readable brain walkthrough markdown must be backed up.'
    Assert-Any $files 'antigravity/brain/*/*.metadata.json' 'Readable brain metadata JSON must be backed up.'

    Assert-None $files '/\.system_generated/' 'Generated transcripts and messages must not be backed up.'
    Assert-None $files '/scratch/' 'Scratch files must not be backed up.'
    Assert-None $files '^antigravity/conversations/' 'Conversation databases must not be backed up.'
    Assert-None $files '^tmp/' 'Temporary files must not be backed up.'
    Assert-None $files '^history/' 'History files must not be backed up.'
    Assert-None $files '\.(db|sqlite|sqlite3|mp4|webm|png|jpg|jpeg|pdf|exe|pb)$' 'Binary, media, and database files must not be backed up.'

    if ($files.Count -lt 20) {
        throw "Dry-run selected too few files: $($files.Count)"
    }
    if ([double]$data.totalSizeBytes -gt 10MB) {
        throw "Dry-run selected too much data: $($data.totalSizeBytes) bytes"
    }

    Write-Host "OK Gemini memory backup dry-run manifest is safe ($($files.Count) files, $($data.totalSizeBytes) bytes)"
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
