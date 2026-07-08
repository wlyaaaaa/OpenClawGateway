param(
    [switch]$DryRun,
    [string]$ManifestPath
)

# =====================================================================
#  backup-gemini-memory.ps1 - Backup safe Gemini / Antigravity memory
# ---------------------------------------------------------------------
#  Mirrors only small, human-readable state into a private GitHub repo.
#  Excludes raw conversations, transcripts, databases, scratch, media,
#  recordings, binaries, and installation identifiers.
# =====================================================================
$ErrorActionPreference = 'Stop'

$src       = "C:\Users\10979\.gemini"
$root      = "E:\Projects\Tools\OpenClawGateway\gemini-memory-backup"
$cloudRepo = "E:\Projects\Backups\gemini-memory"   # private repo: wlyaaaaa/gemini-memory
$keep      = 30
$log       = "E:\Projects\Tools\OpenClawGateway\logs\backup-gemini-memory.log"

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

function Add-File([System.Collections.Generic.List[object]]$files, [string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item = Get-Item -LiteralPath $path
        $files.Add([PSCustomObject]@{
            Source       = $item.FullName
            RelativePath = To-RelPath $item.FullName
            Length       = [int64]$item.Length
        }) | Out-Null
    }
}

function Add-Files([System.Collections.Generic.List[object]]$files, [string]$base, [string]$filter) {
    if (Test-Path -LiteralPath $base) {
        Get-ChildItem -LiteralPath $base -Recurse -File -Filter $filter |
            ForEach-Object { Add-File $files $_.FullName }
    }
}

function Get-GeminiMemoryFiles {
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Gemini directory does not exist: $src"
    }

    $files = [System.Collections.Generic.List[object]]::new()

    Add-File $files (Join-Path $src 'projects.json')
    Add-Files $files (Join-Path $src 'config') '*'
    Add-File $files (Join-Path $src 'antigravity\antigravity_state.pbtxt')
    Add-Files $files (Join-Path $src 'antigravity\annotations') '*.pbtxt'

    $brain = Join-Path $src 'antigravity\brain'
    if (Test-Path -LiteralPath $brain) {
        Get-ChildItem -LiteralPath $brain -Recurse -File |
            Where-Object {
                $rel = To-RelPath $_.FullName
                ($rel -notmatch '/\.system_generated/') -and
                ($rel -notmatch '/scratch/') -and
                (($_.Name -like '*.md') -or ($_.Name -like '*.metadata.json'))
            } |
            ForEach-Object { Add-File $files $_.FullName }
    }

    $files |
        Sort-Object RelativePath -Unique |
        Where-Object {
            $_.RelativePath -notmatch '(^|/)installation_id$' -and
            $_.RelativePath -notmatch '^tmp/' -and
            $_.RelativePath -notmatch '^history/' -and
            $_.RelativePath -notmatch '^antigravity/conversations/' -and
            $_.RelativePath -notmatch '\.(db|sqlite|sqlite3|mp4|webm|png|jpg|jpeg|pdf|exe|pb)$'
        }
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
        '# gemini-memory (private cloud backup)',
        '',
        '> Safe Gemini / Antigravity memory and config backup.',
        '> Synced and pushed by the local scheduled task `Gemini Memory Backup`.',
        '',
        '## Scope',
        '',
        'Included:',
        '',
        '- `projects.json`',
        '- `config/**`',
        '- `antigravity/antigravity_state.pbtxt`',
        '- `antigravity/annotations/*.pbtxt`',
        '- `antigravity/brain/**/*.md`',
        '- `antigravity/brain/**/*.metadata.json`',
        '',
        'Excluded:',
        '',
        '- raw conversations, transcripts, messages, and logs',
        '- `tmp/`, `history/`, and `scratch/`',
        '- conversation DBs, SQLite files, images, videos, recordings, PDFs, and binaries',
        '- installation ids and credential-like files',
        '',
        '## Restore',
        '',
        'Copy the repository contents back to `C:\Users\10979\.gemini\` with the same relative paths. This restores small config and human-readable outputs only, not raw session databases or media.'
    ) -join [Environment]::NewLine
    $content | Out-File -FilePath (Join-Path $path 'README.md') -Encoding utf8
}

$files = @(Get-GeminiMemoryFiles)
if ($files.Count -eq 0) {
    throw "No safe Gemini memory files selected."
}

if ($DryRun) {
    Write-Manifest $files $ManifestPath
    exit 0
}

Log "=== Gemini Memory Backup - start ==="

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
            & git -C $cloudRepo commit -m ("gemini memory snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>$null | Out-Null
            & git -C $cloudRepo push -u origin main 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Log "[OK] cloud backup pushed (private: wlyaaaaa/gemini-memory)" }
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
