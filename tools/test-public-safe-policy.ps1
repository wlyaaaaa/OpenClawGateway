$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$violations = @()

function Add-Violation([string]$message) {
    $script:violations += $message
}

function Read-Text([string]$relativePath) {
    Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw -Encoding utf8
}

$tracked = git -C $root ls-files

foreach ($path in $tracked) {
    if ($path -like 'journal/*') { Add-Violation "tracked private journal file: $path" }
    if ($path -eq 'CLAUDE.md') { Add-Violation 'tracked private handoff file: CLAUDE.md' }
    if ($path -eq 'docs/AUDIT.md') { Add-Violation 'tracked private security audit: docs/AUDIT.md' }
    if ($path -eq 'openclaw_task.xml') { Add-Violation 'tracked machine-bound task XML: openclaw_task.xml' }
    if ($path -eq 'README.pdf' -or $path -like 'docs/*.pdf') { Add-Violation "tracked generated PDF: $path" }
}

$telegramUserIdProbe = ('832' + '097' + '0051')
$hardcodedIdHits = git -C $root grep -n --fixed-strings $telegramUserIdProbe -- . ':(exclude)tools/test-public-safe-policy.ps1' 2>$null
if ($hardcodedIdHits) {
    Add-Violation "tracked files contain hardcoded Telegram user ID:`n$($hardcodedIdHits -join "`n")"
}

$gitignore = Read-Text '.gitignore'
foreach ($requiredPattern in @('journal/', '*.pdf')) {
    $escapedPattern = [regex]::Escape($requiredPattern)
    if ($gitignore -notmatch "(?m)^$escapedPattern\s*$") {
        Add-Violation ".gitignore must ignore $requiredPattern"
    }
}

$setup = Read-Text 'bootstrap\setup.ps1'
if ($setup -notmatch "Disable-ScheduledTask\s+-TaskName\s+['""]OpenClaw Update['""]") {
    Add-Violation 'bootstrap/setup.ps1 must leave OpenClaw Update disabled after registration'
}

$maintenance = Read-Text 'docs\MAINTENANCE.md'
if ($maintenance -notmatch "Disable-ScheduledTask\s+-TaskName\s+['""]OpenClaw Update['""]") {
    Add-Violation 'docs/MAINTENANCE.md must document disabled OpenClaw Update restoration'
}

$guardian = Read-Text 'openclaw_silent_boot_guardian.ps1'
if ($guardian -notmatch '--max-old-space-size=1536') {
    Add-Violation 'openclaw_silent_boot_guardian.ps1 direct node startup must carry the 1536MB heap guard'
}

$autopush = Read-Text 'tools\auto-archive-push.ps1'
foreach ($needle in @('git -C $repo ls-files', 'journal/', 'logs/', '.secrets/', 'secrets-backup/', 'auth-profiles.json', 'openclaw_task.xml')) {
    if ($autopush -notlike "*$needle*") {
        Add-Violation "tools/auto-archive-push.ps1 missing public-safe guard: $needle"
    }
}

if ($violations.Count -gt 0) {
    throw "Public-safe policy violations:`n$($violations -join "`n")"
}

Write-Host 'PASS: public-safe policy guards are in place.'
