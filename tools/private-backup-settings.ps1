$PrivateBackupSettingsSchema = 'openclaw_gateway.private_backup_settings.v1'
$PrivateBackupSettingsRequiredKeys = @{
    codex_memory = @(
        'source_root',
        'snapshot_root',
        'cloud_repo',
        'log_file'
    )
    gemini_memory = @(
        'source_root',
        'snapshot_root',
        'hot_snapshot_root',
        'cloud_repo',
        'log_file'
    )
    claude_memory = @(
        'source_root',
        'snapshot_root',
        'hot_snapshot_root',
        'cloud_repo',
        'log_file'
    )
    openclaw = @(
        'config_root',
        'workspace_root',
        'snapshot_root',
        'hot_snapshot_root',
        'cloud_repo',
        'log_file'
    )
}

function Throw-PrivateBackupSettingsKeyMissing([string]$Key) {
    throw "Missing required private backup settings key: $Key"
}

function Test-PrivateBackupAbsolutePath([object]$Value) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }

    return ([string]$Value -match '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)')
}

function Read-PrivateBackupSettingsJson([string]$SettingsPath) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($SettingsPath)
        $offset = if (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        ) { 3 } else { 0 }
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        return $utf8.GetString($bytes, $offset, $bytes.Length - $offset)
    } catch {
        Throw-PrivateBackupSettingsKeyMissing 'settings_json'
    }
}

function Get-PrivateBackupSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefaultSettingsPath,

        [Parameter(Mandatory)]
        [ValidateSet('codex_memory', 'gemini_memory', 'claude_memory', 'openclaw')]
        [string]$Group
    )

    $settingsPath = if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_PRIVATE_BACKUP_SETTINGS)) {
        $DefaultSettingsPath
    } else {
        $env:OPENCLAW_PRIVATE_BACKUP_SETTINGS
    }
    $hasSettingsFile = $false
    try {
        if (-not [string]::IsNullOrWhiteSpace($settingsPath)) {
            $hasSettingsFile = Test-Path -LiteralPath $settingsPath -PathType Leaf
        }
    } catch {
        $hasSettingsFile = $false
    }
    if (-not $hasSettingsFile) {
        Throw-PrivateBackupSettingsKeyMissing 'settings_file'
    }

    try {
        $settings = Read-PrivateBackupSettingsJson $settingsPath | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Throw-PrivateBackupSettingsKeyMissing 'settings_json'
    }

    try {
        $schemaProperty = $settings.PSObject.Properties['schema']
    } catch {
        Throw-PrivateBackupSettingsKeyMissing 'schema'
    }
    if ($null -eq $schemaProperty -or $schemaProperty.Value -ne $PrivateBackupSettingsSchema) {
        Throw-PrivateBackupSettingsKeyMissing 'schema'
    }

    try {
        $groupProperty = $settings.PSObject.Properties[$Group]
    } catch {
        Throw-PrivateBackupSettingsKeyMissing $Group
    }
    if ($null -eq $groupProperty -or $null -eq $groupProperty.Value) {
        Throw-PrivateBackupSettingsKeyMissing $Group
    }

    $result = [ordered]@{}
    foreach ($key in $PrivateBackupSettingsRequiredKeys[$Group]) {
        try {
            $property = $groupProperty.Value.PSObject.Properties[$key]
        } catch {
            Throw-PrivateBackupSettingsKeyMissing "$Group.$key"
        }
        if ($null -eq $property -or -not (Test-PrivateBackupAbsolutePath $property.Value)) {
            Throw-PrivateBackupSettingsKeyMissing "$Group.$key"
        }
        $result[$key] = [string]$property.Value
    }

    return [PSCustomObject]$result
}
