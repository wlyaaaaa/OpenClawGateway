#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$violations = [Collections.Generic.List[string]]::new()

function Add-Violation([string]$Message) {
    $violations.Add($Message)
}

function Read-TrackedText([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding utf8
}

$tracked = @(
    git -C $root ls-files --cached --others --exclude-standard |
        Where-Object { Test-Path -LiteralPath (Join-Path $root $_) }
)
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }

$forbiddenPaths = @(
    'openclaw_run_hidden.vbs',
    'set-api.ps1',
    'disable-openclaw-api.ps1',
    'enable-openclaw-api.ps1',
    'tools/query_weflow.ps1',
    'tools/query_weflow2.ps1',
    'tools/query_weflow3.ps1',
    'tools/update_sqlite_profiles.py',
    'tools/register_deepseek.py',
    'tools/register_model.py',
    'tools/register_qwen37plus.py',
    'tools/apply-deepseek.ps1',
    'tools/apply-qwen36.ps1',
    'tools/apply-qwen37plus.ps1'
    'tools/switch-model.ps1'
    'tools/set-thinking.ps1'
    'tools/restart_gateway.ps1'
    'tools/remove_bom.py'
    'tools/build_docs_pdf.py'
    'bootstrap/cline-rules/openclaw-service.md'
    'bootstrap/skills/cline-coding/SKILL.md'
)
foreach ($path in $tracked) {
    if ($path -in $forbiddenPaths) { Add-Violation "retired file is still tracked: $path" }
    if ($path -like 'public/*') { Add-Violation "unrelated legacy site is still tracked: $path" }
    if ($path -like 'journal/*') { Add-Violation "private journal is tracked: $path" }
    if ($path -eq 'CLAUDE.md') { Add-Violation 'private handoff is tracked: CLAUDE.md' }
    if ($path -eq 'docs/AUDIT.md') { Add-Violation 'private audit artifact is tracked: docs/AUDIT.md' }
    if ($path -eq 'openclaw_task.xml') { Add-Violation 'machine task export is tracked: openclaw_task.xml' }
    if ($path -eq 'README.pdf' -or $path -like 'docs/*.pdf') {
        Add-Violation "generated PDF is tracked: $path"
    }
}

$textExtensions = @('.md', '.ps1', '.py', '.json', '.json5', '.yml', '.yaml', '.vbs', '.txt')
foreach ($relativePath in $tracked) {
    if ([IO.Path]::GetExtension($relativePath).ToLowerInvariant() -notin $textExtensions) { continue }
    $text = Read-TrackedText $relativePath
    if ($null -eq $text) { continue }

    if ($text -match '(?i)C:\\Users\\(?!Public\\|<|USERNAME\\)[A-Za-z0-9._-]+\\') {
        Add-Violation "machine user path in $relativePath"
    }
    if ($text -match '(?i)\bsk-[A-Za-z0-9][A-Za-z0-9._-]{11,}') {
        Add-Violation "secret-like API key in $relativePath"
    }
    if ($text -match '(?i)Authorization\s*[:=]\s*Bearer\s+(?!<|\$|\{)[A-Za-z0-9._-]{10,}') {
        Add-Violation "literal bearer credential in $relativePath"
    }
    if ($relativePath -ne 'tools/test-public-safe-policy.ps1' -and
        $text -match '(?i)(?:[A-Z]:\\[^\r\n"'']*\\(?:Backups|80_Backup)\\|private[-_]handovers|(?:private|私有)[^\r\n]{0,80}\b[a-z0-9_.-]+/[a-z0-9_.-]+|https?://github\.com/[^/\s]+/[^)\s]*(?:backup|memory))') {
        Add-Violation "private backup coordinate or machine path in $relativePath"
    }
    if ($text -match '(?<!\d)\d{9,12}(?!\d)') {
        Add-Violation "account-like long numeric identifier in $relativePath"
    }
    foreach ($emailMatch in [regex]::Matches($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b')) {
        if ($emailMatch.Value -notmatch '(?i)@example\.invalid$') {
            Add-Violation "account-specific email in $relativePath"
        }
    }
}

$gitignore = Read-TrackedText '.gitignore'
foreach ($requiredPattern in @('journal/', '*.pdf', '*.tar.gz', 'testResults*.xml', 'tools/private-backup.local.json')) {
    if ($gitignore -notmatch ('(?m)^' + [regex]::Escape($requiredPattern) + '\s*$')) {
        Add-Violation ".gitignore must ignore $requiredPattern"
    }
}

$guardian = Read-TrackedText 'openclaw_silent_boot_guardian.ps1'
foreach ($forbidden in @('SetEnvironmentVariable', 'Register-ScheduledTask', 'Stop-Process', 'openclaw_run_hidden.vbs')) {
    if ($guardian -match [regex]::Escape($forbidden)) {
        Add-Violation "guardian retains retired machine-specific behavior: $forbidden"
    }
}
foreach ($required in @('[switch]$Repair', "'gateway', 'install'", "'gateway', 'status'", '--require-rpc')) {
    if (-not $guardian.Contains($required)) {
        Add-Violation "guardian is missing official read/repair contract: $required"
    }
}

$api = Read-TrackedText 'api.ps1'
foreach ($required in @('global_zero_cost_enforced = $false', 'mode_switch_available = $false', 'session_and_job_overrides_checked = $false', "exit 2", "'openclaw_gateway.cost_posture.v2'")) {
    if (-not $api.Contains($required)) { Add-Violation "api.ps1 is missing truthful cost posture: $required" }
}

$autopush = Read-TrackedText 'tools\auto-archive-push.ps1'
foreach ($needle in @("Arguments @('ls-files')", 'journal/', 'logs/', '.secrets/', 'secrets-backup/', 'auth-profiles.json', 'openclaw_task.xml')) {
    if ($autopush -notlike "*$needle*") {
        Add-Violation "auto-archive public guard missing: $needle"
    }
}

$gitSync = Read-TrackedText 'tools\git-cloud-sync.ps1'
foreach ($needle in @("'fetch', '--quiet', '--prune'", "'rev-list', '--left-right', '--count'", "'ls-remote', '--exit-code'", 'Fresh remote OID mismatch', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE')) {
    if ($gitSync -notlike "*$needle*") {
        Add-Violation "verified Git sync guard missing: $needle"
    }
}

foreach ($relativePath in $tracked | Where-Object { $_ -match '\.md$' }) {
    $markdown = Read-TrackedText $relativePath
    foreach ($match in [regex]::Matches($markdown, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = [string]$match.Groups[1].Value
        if ($target -match '^(https?://|mailto:|#)' -or $target -match '[<>*]') { continue }
        $targetPath = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }
        $base = Split-Path -Parent (Join-Path $root $relativePath)
        $resolved = Join-Path $base ([Uri]::UnescapeDataString($targetPath))
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Violation "broken relative Markdown link in $relativePath -> $target"
        }
    }
}

if ($violations.Count -gt 0) {
    throw "Public-safe policy violations:`n$($violations -join "`n")"
}

[Console]::WriteLine('PASS public repository boundary, retired surfaces, and documentation links')
