$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scripts = @(
    Join-Path $root 'disable-openclaw-api.ps1'
    Join-Path $root 'enable-openclaw-api.ps1'
)

$violations = @()

foreach ($script in $scripts) {
    $text = Get-Content -LiteralPath $script -Raw -Encoding utf8

    foreach ($channel in @('telegram', 'feishu')) {
        $enabledPathPattern = "channels\.$channel\.enabled"
        if ($text -match $enabledPathPattern) {
            $violations += "$([IO.Path]::GetFileName($script)) writes $enabledPathPattern"
        }

        $jsonBlockPattern = "`"$channel`"\s*:\s*\{[^}]*`"enabled`"\s*:"
        if ($text -match $jsonBlockPattern) {
            $violations += "$([IO.Path]::GetFileName($script)) patches channels.$channel.enabled"
        }
    }
}

if ($violations.Count -gt 0) {
    throw "API scripts must not modify telegram/feishu enabled flags: $($violations -join '; ')"
}

Write-Host 'PASS: API scripts do not modify telegram/feishu enabled flags.'
