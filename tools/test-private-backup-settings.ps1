param()

$ErrorActionPreference = 'Stop'

$helper = Join-Path $PSScriptRoot 'private-backup-settings.ps1'
if (-not (Test-Path -LiteralPath $helper)) {
    throw "Missing settings helper: $helper"
}
. $helper

function New-TestSettings {
    param([Parameter(Mandatory)][string]$Root)

    return [ordered]@{
        schema = 'openclaw_gateway.private_backup_settings.v1'
        gemini_memory = [ordered]@{
            source_root = Join-Path $Root 'gemini\source'
            snapshot_root = Join-Path $Root 'gemini\snapshot'
            hot_snapshot_root = Join-Path $Root 'gemini\hot-snapshot'
            cloud_repo = Join-Path $Root 'gemini\cloud-repo'
            log_file = Join-Path $Root 'gemini\logs\backup.log'
        }
        claude_memory = [ordered]@{
            source_root = Join-Path $Root 'claude\source'
            snapshot_root = Join-Path $Root 'claude\snapshot'
            hot_snapshot_root = Join-Path $Root 'claude\hot-snapshot'
            cloud_repo = Join-Path $Root 'claude\cloud-repo'
            log_file = Join-Path $Root 'claude\logs\backup.log'
        }
        openclaw = [ordered]@{
            config_root = Join-Path $Root 'openclaw\config'
            workspace_root = Join-Path $Root 'openclaw\workspace'
            snapshot_root = Join-Path $Root 'openclaw\snapshot'
            hot_snapshot_root = Join-Path $Root 'openclaw\hot-snapshot'
            cloud_repo = Join-Path $Root 'openclaw\cloud-repo'
            log_file = Join-Path $Root 'openclaw\logs\backup.log'
        }
    }
}

function Write-TestSettings {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$Path
    )

    $Settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Assert-SettingsFailure {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$ExpectedKey,
        [string]$PrivateMarker
    )

    $message = $null
    try {
        & $Action
    } catch {
        $message = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($message)) {
        throw "Expected settings validation failure for $ExpectedKey."
    }
    $expectedMessage = "Missing required private backup settings key: $ExpectedKey"
    if ($message -ne $expectedMessage) {
        throw "Unexpected settings validation message for $($ExpectedKey): $message"
    }
    if ($PrivateMarker -and $message.Contains($PrivateMarker)) {
        throw "Settings validation leaked a private value for $ExpectedKey."
    }
}

$requiredKeys = @{
    gemini_memory = @('source_root', 'snapshot_root', 'hot_snapshot_root', 'cloud_repo', 'log_file')
    claude_memory = @('source_root', 'snapshot_root', 'hot_snapshot_root', 'cloud_repo', 'log_file')
    openclaw = @('config_root', 'workspace_root', 'snapshot_root', 'hot_snapshot_root', 'cloud_repo', 'log_file')
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'openclaw-private-backup-settings-{0}-{1}' -f $PID, [Guid]::NewGuid().ToString('N')
)
$previousSettings = $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $settingsPath = Join-Path $testRoot 'private-backup.local.json'
    $settings = New-TestSettings -Root $testRoot
    Write-TestSettings -Settings $settings -Path $settingsPath
    Remove-Item -Path Env:OPENCLAW_PRIVATE_BACKUP_SETTINGS -ErrorAction SilentlyContinue

    foreach ($group in $requiredKeys.Keys) {
        $resolved = Get-PrivateBackupSettings -DefaultSettingsPath $settingsPath -Group $group
        foreach ($key in $requiredKeys[$group]) {
            $expected = [string]$settings[$group][$key]
            $actual = [string]$resolved.PSObject.Properties[$key].Value
            if ($actual -ne $expected) {
                throw "Settings helper returned the wrong value for $group.$key."
            }
        }
    }

    $overridePath = Join-Path $testRoot 'override.json'
    $overrideSettings = New-TestSettings -Root (Join-Path $testRoot 'override')
    Write-TestSettings -Settings $overrideSettings -Path $overridePath
    $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS = $overridePath
    $overrideResolved = Get-PrivateBackupSettings -DefaultSettingsPath (Join-Path $testRoot 'missing-default.json') -Group 'gemini_memory'
    if ([string]$overrideResolved.source_root -ne [string]$overrideSettings.gemini_memory.source_root) {
        throw 'OPENCLAW_PRIVATE_BACKUP_SETTINGS did not override the default settings file.'
    }
    Remove-Item -Path Env:OPENCLAW_PRIVATE_BACKUP_SETTINGS -ErrorAction SilentlyContinue

    Assert-SettingsFailure {
        Get-PrivateBackupSettings -DefaultSettingsPath (Join-Path $testRoot 'missing.json') -Group 'gemini_memory'
    } 'settings_file'

    $malformedPath = Join-Path $testRoot 'malformed.json'
    [System.IO.File]::WriteAllText($malformedPath, '{ not json', [System.Text.UTF8Encoding]::new($false))
    Assert-SettingsFailure {
        Get-PrivateBackupSettings -DefaultSettingsPath $malformedPath -Group 'gemini_memory'
    } 'settings_json'

    $badSchemaPath = Join-Path $testRoot 'bad-schema.json'
    $badSchema = New-TestSettings -Root $testRoot
    $badSchema.schema = 'wrong-schema'
    Write-TestSettings -Settings $badSchema -Path $badSchemaPath
    Assert-SettingsFailure {
        Get-PrivateBackupSettings -DefaultSettingsPath $badSchemaPath -Group 'gemini_memory'
    } 'schema'

    $missingKeyPath = Join-Path $testRoot 'missing-key.json'
    $missingKey = New-TestSettings -Root $testRoot
    $missingKey.gemini_memory.Remove('cloud_repo') | Out-Null
    Write-TestSettings -Settings $missingKey -Path $missingKeyPath
    Assert-SettingsFailure {
        Get-PrivateBackupSettings -DefaultSettingsPath $missingKeyPath -Group 'gemini_memory'
    } 'gemini_memory.cloud_repo'

    $privateMarker = 'private-value-must-not-appear'
    $relativePath = Join-Path $testRoot 'relative-key.json'
    $relativeKey = New-TestSettings -Root $testRoot
    $relativeKey.gemini_memory.cloud_repo = "$privateMarker\relative-repository"
    Write-TestSettings -Settings $relativeKey -Path $relativePath
    Assert-SettingsFailure {
        Get-PrivateBackupSettings -DefaultSettingsPath $relativePath -Group 'gemini_memory'
    } 'gemini_memory.cloud_repo' $privateMarker

    $effectsRoot = Join-Path $testRoot 'side-effects-must-not-exist'
    $scriptChecks = @(
        [PSCustomObject]@{
            Group = 'gemini_memory'
            Script = 'backup-gemini-memory.ps1'
            Arguments = @('-DryRun', '-ManifestPath', (Join-Path $testRoot 'gemini-manifest.json'))
        },
        [PSCustomObject]@{
            Group = 'claude_memory'
            Script = 'backup-memory.ps1'
            Arguments = @()
        },
        [PSCustomObject]@{
            Group = 'openclaw'
            Script = 'backup-openclaw.ps1'
            Arguments = @()
        }
    )

    foreach ($check in $scriptChecks) {
        $invalidSettings = New-TestSettings -Root (Join-Path $effectsRoot $privateMarker)
        $invalidSettings[$check.Group].Remove('cloud_repo') | Out-Null
        $invalidPath = Join-Path $testRoot ("invalid-{0}.json" -f $check.Group)
        Write-TestSettings -Settings $invalidSettings -Path $invalidPath
        $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS = $invalidPath

        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $check.Script)) + @($check.Arguments)
        $savedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& powershell.exe @arguments 2>&1 | ForEach-Object { $_.ToString() })
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
        if ($exitCode -eq 0) {
            throw "Expected $($check.Script) to fail before side effects."
        }
        $outputText = $output -join [Environment]::NewLine
        $expectedMessage = "Missing required private backup settings key: $($check.Group).cloud_repo"
        if ($outputText -notmatch [regex]::Escape($expectedMessage)) {
            throw "$($check.Script) did not report the missing settings key."
        }
        if ($outputText -match [regex]::Escape($privateMarker)) {
            throw "$($check.Script) leaked a configured private value."
        }
        if (Test-Path -LiteralPath $effectsRoot) {
            throw "$($check.Script) created a directory before settings validation."
        }
    }

    Write-Host 'OK private backup settings validate all groups and fail before backup side effects'
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
