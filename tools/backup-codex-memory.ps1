param(
    [switch]$DryRun,
    [string]$ManifestPath
)

# =====================================================================
#  backup-codex-memory.ps1 - Backup safe Codex memory and config
# ---------------------------------------------------------------------
#  Mirrors only small, human-readable state into a private GitHub repo.
#  Excludes auth, raw sessions, SQLite databases, logs, caches, plugins,
#  packages, temporary files, import transcripts, and installation ids.
# =====================================================================
$ErrorActionPreference = 'Stop'

$src       = "C:\Users\10979\.codex"
$root      = "E:\Projects\Tools\OpenClawGateway\codex-memory-backup"
$cloudRepo = "E:\CodexMemoryBackup"   # private repo: wlyaaaaa/codex-memory
$keep      = 30
$log       = "E:\Projects\Tools\OpenClawGateway\logs\backup-codex-memory.log"

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

function To-RelPath([string]$path) {
    $rel = $path.Substring($src.Length).TrimStart('\', '/')
    return ($rel -replace '\\', '/')
}

function Is-SafeCodexPath([string]$relativePath) {
    if ($relativePath -match '(^|/)\.git(/|$)') { return $false }
    if ($relativePath -match '^(auth\.json|installation_id|session_index\.jsonl|models_cache\.json)$') { return $false }
    if ($relativePath -match '^\.codex-global-state\.json') { return $false }
    if ($relativePath -match '^claude-cowork-') { return $false }
    if ($relativePath -match '^external_agent_session_imports\.json$') { return $false }
    if ($relativePath -match '^(sessions|plugins|packages|cache|tmp|\.tmp|sqlite|process_manager|pets)/') { return $false }
    if ($relativePath -match '\.(sqlite|sqlite3|db|db-shm|db-wal|jsonl)$') { return $false }
    return $true
}

function Add-File([System.Collections.Generic.List[object]]$files, [string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item = Get-Item -LiteralPath $path
        $rel = To-RelPath $item.FullName
        if (Is-SafeCodexPath $rel) {
            $files.Add([PSCustomObject]@{
                Source       = $item.FullName
                RelativePath = $rel
                Length       = [int64]$item.Length
            }) | Out-Null
        }
    }
}

function Add-Files([System.Collections.Generic.List[object]]$files, [string]$base) {
    if (Test-Path -LiteralPath $base) {
        Get-ChildItem -LiteralPath $base -Recurse -File -Force |
            ForEach-Object { Add-File $files $_.FullName }
    }
}

function Get-CodexMemoryFiles {
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Codex directory does not exist: $src"
    }

    $files = [System.Collections.Generic.List[object]]::new()

    Add-File $files (Join-Path $src 'AGENTS.md')
    Add-File $files (Join-Path $src 'config.toml')
    Add-File $files (Join-Path $src 'version.json')
    Add-File $files (Join-Path $src 'chrome-native-hosts-v2.json')
    Add-File $files (Join-Path $src 'browser\config.toml')
    Add-File $files (Join-Path $src 'computer-use\config.json')
    Add-File $files (Join-Path $src 'vendor_imports\skills-curated-cache.json')
    Add-Files $files (Join-Path $src 'memories')
    Add-Files $files (Join-Path $src 'skills')

    $files |
        Sort-Object RelativePath -Unique |
        Where-Object { Is-SafeCodexPath $_.RelativePath }
}

function Write-Manifest($files, [string]$path) {
    $manifest = [PSCustomObject]@{
        sourceRoot     = $src
        totalSizeBytes = [int64](($files | Measure-Object Length -Sum).Sum)
        files          = @($files | ForEach-Object { $_.RelativePath })
    }
    $json = $manifest | ConvertTo-Json -Depth 5
    if ($path) {
        $parent = Split-Path $path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $json | Out-File -FilePath $path -Encoding utf8
    } else {
        Write-Output $json
    }
}

function Copy-SelectedFiles($files, [string]$destinationRoot) {
    foreach ($file in $files) {
        $dest = Join-Path $destinationRoot ($file.RelativePath -replace '/', '\')
        $parent = Split-Path $dest
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.Source -Destination $dest -Force
    }
}

function Clear-CloudRepo([string]$path) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ($resolved -ne $cloudRepo) {
        throw "Refusing to clear unexpected cloud repo path: $resolved"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $resolved '.git'))) {
        throw "Cloud repo is not initialized: $resolved"
    }
    Get-ChildItem -LiteralPath $resolved -Force |
        Where-Object { $_.Name -ne '.git' } |
        Remove-Item -Recurse -Force
}

function Write-Readme([string]$path) {
    $content = @(
        '# codex-memory (private cloud backup)',
        '',
        '> Safe Codex memory, config, and installed-skill backup.',
        '> Synced and pushed by the local scheduled task `Codex Memory Backup`.',
        '',
        '## Scope',
        '',
        'Included:',
        '',
        '- `AGENTS.md`',
        '- `config.toml`',
        '- `version.json`',
        '- `chrome-native-hosts-v2.json`',
        '- `browser/config.toml`',
        '- `computer-use/config.json`',
        '- `vendor_imports/skills-curated-cache.json`',
        '- `memories/**` except nested `.git/**`',
        '- `skills/**`',
        '',
        'Excluded:',
        '',
        '- `auth.json` and installation identifiers',
        '- raw sessions, imported transcripts, session indexes, and JSONL logs',
        '- SQLite databases, WAL/SHM files, runtime state, and model cache',
        '- plugin cache, package cache, temp folders, process manager state, and local pet state',
        '',
        '## Restore',
        '',
        'Copy the repository contents back to `C:\Users\10979\.codex\` with the same relative paths. This restores small config, memories, and skill files only, not auth, raw sessions, caches, or runtime databases.'
    ) -join [Environment]::NewLine
    $content | Out-File -FilePath (Join-Path $path 'README.md') -Encoding utf8
}

$files = @(Get-CodexMemoryFiles)
if ($files.Count -eq 0) {
    throw "No safe Codex memory files selected."
}

if ($DryRun) {
    Write-Manifest $files $ManifestPath
    exit 0
}

Log "=== Codex Memory Backup - start ==="

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $root $stamp
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-SelectedFiles $files $dst
$totalBytes = [int64](($files | Measure-Object Length -Sum).Sum)
Log "[OK] local snapshot $($files.Count) files / $totalBytes bytes -> $dst"

$dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
if ($dirs.Count -gt $keep) {
    $dirs | Select-Object -Skip $keep | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Log "[..] removed old backup $($_.Name)"
    }
}

if (Test-Path -LiteralPath (Join-Path $cloudRepo '.git')) {
    $eapSave = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Clear-CloudRepo $cloudRepo
        Copy-SelectedFiles $files $cloudRepo
        Write-Readme $cloudRepo
        Write-Manifest $files (Join-Path $cloudRepo 'MANIFEST.json')

        $branch = (& git -C $cloudRepo branch --show-current 2>$null).Trim()
        if (-not $branch) {
            & git -C $cloudRepo checkout -B main 2>$null | Out-Null
        }

        $changed = (& git -C $cloudRepo status --porcelain 2>$null) -join ''
        if ($changed) {
            & git -C $cloudRepo add -A 2>$null | Out-Null
            & git -C $cloudRepo commit -m ("codex memory snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>$null | Out-Null
            & git -C $cloudRepo push -u origin main 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Log "[OK] cloud backup pushed (private: wlyaaaaa/codex-memory)" }
            else { Log "[WARN] cloud backup push exit code $LASTEXITCODE (local snapshot succeeded)" }
        } else {
            Log "[..] cloud backup unchanged; skipped push"
        }
    } catch {
        Log "[WARN] cloud backup failed (local snapshot succeeded): $_"
    } finally {
        $ErrorActionPreference = $eapSave
    }
} else {
    Log "[..] cloud backup repo not initialized ($cloudRepo); skipped"
}

Log "=== done ==="
