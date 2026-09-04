#Requires -Version 7.0
<#
  Isolated fixture tests for setup-codeg-bridge.ps1.
  The script only touches a unique directory below OPENCLAW_TEST_TEMP_ROOT or TEMP.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:pass = 0
$script:fail = 0
$setupScript = Join-Path $PSScriptRoot 'setup-codeg-bridge.ps1'
$tempBase = if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_TEST_TEMP_ROOT)) {
    [IO.Path]::GetTempPath()
}
else {
    $env:OPENCLAW_TEST_TEMP_ROOT
}
$testRoot = Join-Path $tempBase ("openclaw-codeg-bridge-test-$PID-$([Guid]::NewGuid().ToString('N'))")

function Assert-True {
    param([bool]$Condition, [string]$Label)

    if ($Condition) {
        $script:pass++
    }
    else {
        $script:fail++
        [Console]::Error.WriteLine("FAIL: $Label")
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)

    Assert-True ($Expected -eq $Actual) $Label
}

function ConvertTo-CompactJson {
    param([Parameter(Mandatory)]$Value)

    return ($Value | ConvertTo-Json -Depth 64 -Compress)
}

function Assert-JsonEqual {
    param($Expected, $Actual, [string]$Label)

    Assert-Equal (ConvertTo-CompactJson $Expected) (ConvertTo-CompactJson $Actual) $Label
}

function Test-ByteEqual {
    param([byte[]]$Expected, [byte[]]$Actual)

    if ($Expected.Length -ne $Actual.Length) { return $false }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) { return $false }
    }
    return $true
}

function Test-HasUtf8Bom {
    param([byte[]]$Bytes)

    return $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
}

function Read-JsonFile {
    param([string]$Path)

    return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable -Depth 64)
}

function Invoke-BridgeSetup {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$FakePwsh,
        [Parameter(Mandatory)][string]$FakeLauncher
    )

    $parameters = @{
        ClineSettingsPath = $SettingsPath
        GatewayUrl = 'http://127.0.0.1:18789'
        SkipProbe = $true
        ManagedPwshPath = $FakePwsh
        ManagedLauncherPath = $FakeLauncher
    }
    & $setupScript @parameters | Out-Null
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $fixtureBin = Join-Path $testRoot 'fixture-bin'
    New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
    $fakePwsh = Join-Path $fixtureBin 'pwsh.exe'
    $fakeLauncher = Join-Path $fixtureBin 'Start-OpenClawMcpBridge.ps1'
    [System.IO.File]::WriteAllText($fakePwsh, '', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($fakeLauncher, '', [System.Text.UTF8Encoding]::new($false))

    # Managed launcher: retain unknown root keys and unrelated MCP definitions.
    $managedSettings = Join-Path $testRoot 'managed\cline_mcp_settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $managedSettings) -Force | Out-Null
    $managedFixture = @'
{
  "theme": "dark",
  "customRoot": { "nested": [1, { "enabled": true }] },
  "mcpServers": {
    "existing-tool": {
      "type": "stdio",
      "command": "existing-tool.exe",
      "args": ["--retain"],
      "env": { "FIXTURE": "keep" }
    },
    "openclaw-bridge": {
      "type": "stdio",
      "command": "stale-bridge.exe",
      "args": ["--stale"],
      "env": { "STALE": "replace" }
    }
  }
}
'@
    [System.IO.File]::WriteAllText($managedSettings, $managedFixture, [System.Text.UTF8Encoding]::new($false))
    $managedOriginalBytes = [System.IO.File]::ReadAllBytes($managedSettings)
    $managedOriginal = Read-JsonFile $managedSettings

    Invoke-BridgeSetup -SettingsPath $managedSettings -FakePwsh $fakePwsh -FakeLauncher $fakeLauncher
    $managedAfterFirst = Read-JsonFile $managedSettings
    $managedFirstBytes = [System.IO.File]::ReadAllBytes($managedSettings)
    $managedBridge = $managedAfterFirst['mcpServers']['openclaw-bridge']
    Assert-JsonEqual $managedOriginal['customRoot'] $managedAfterFirst['customRoot'] 'managed-preserves-unknown-root-object'
    Assert-Equal $managedOriginal['theme'] $managedAfterFirst['theme'] 'managed-preserves-unknown-root-scalar'
    Assert-JsonEqual $managedOriginal['mcpServers']['existing-tool'] $managedAfterFirst['mcpServers']['existing-tool'] 'managed-preserves-other-mcp-server'
    Assert-Equal 'stdio' $managedBridge['type'] 'managed-bridge-type'
    Assert-Equal $fakePwsh $managedBridge['command'] 'managed-bridge-controlled-pwsh'
    Assert-JsonEqual @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $fakeLauncher) $managedBridge['args'] 'managed-bridge-launcher-args'
    Assert-Equal 'http://127.0.0.1:18789' $managedBridge['env']['OPENCLAW_URL'] 'managed-bridge-url'
    Assert-True (-not $managedBridge['env'].ContainsKey('OPENCLAW_GATEWAY_PASSWORD')) 'managed-bridge-has-no-password'
    Assert-True (-not $managedBridge['env'].ContainsKey('STALE')) 'managed-upserts-existing-bridge'
    Assert-True (-not (Test-HasUtf8Bom $managedFirstBytes)) 'managed-output-is-utf8-without-bom'

    $managedBackup = "$managedSettings.openclaw-bridge.bak"
    Assert-True (Test-Path -LiteralPath $managedBackup -PathType Leaf) 'managed-creates-one-recovery-backup'
    Assert-True (Test-ByteEqual $managedOriginalBytes ([System.IO.File]::ReadAllBytes($managedBackup))) 'managed-backup-preserves-original-bytes'

    Invoke-BridgeSetup -SettingsPath $managedSettings -FakePwsh $fakePwsh -FakeLauncher $fakeLauncher
    $managedSecondBytes = [System.IO.File]::ReadAllBytes($managedSettings)
    Assert-True (Test-ByteEqual $managedFirstBytes $managedSecondBytes) 'managed-repeat-is-byte-idempotent'
    Assert-True (Test-ByteEqual $managedOriginalBytes ([System.IO.File]::ReadAllBytes($managedBackup))) 'managed-repeat-does-not-replace-backup'
    Assert-Equal 1 @((Get-ChildItem -LiteralPath (Split-Path -Parent $managedSettings) -Filter 'cline_mcp_settings.json.openclaw-bridge.bak')).Count 'managed-repeat-does-not-create-extra-backups'

    # The documented `powershell` entry point remains usable on Windows PowerShell 5.1.
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $windowsPowerShell) {
        $ps51Settings = Join-Path $testRoot 'windows-powershell\cline_mcp_settings.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $ps51Settings) -Force | Out-Null
        [System.IO.File]::WriteAllText($ps51Settings, '{"retain":{"value":1},"mcpServers":{"keep":{"command":"keep.exe"}}}', [System.Text.UTF8Encoding]::new($false))
        $ps51Arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $setupScript,
            '-ClineSettingsPath', $ps51Settings,
            '-ManagedPwshPath', $fakePwsh,
            '-ManagedLauncherPath', $fakeLauncher,
            '-GatewayUrl', 'http://127.0.0.1:18789',
            '-SkipProbe'
        )
        & $windowsPowerShell.Source @ps51Arguments | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'windows-powershell-5-compatibility-exit'
        $ps51After = Read-JsonFile $ps51Settings
        Assert-Equal 1 $ps51After['retain']['value'] 'windows-powershell-5-preserves-root-key'
        Assert-Equal $fakePwsh $ps51After['mcpServers']['openclaw-bridge']['command'] 'windows-powershell-5-writes-bridge'
    }

    # Preserve the original create-if-missing behavior without touching a real profile.
    $newSettings = Join-Path $testRoot 'new\nested\cline_mcp_settings.json'
    Invoke-BridgeSetup -SettingsPath $newSettings -FakePwsh $fakePwsh -FakeLauncher $fakeLauncher
    $newAfter = Read-JsonFile $newSettings
    Assert-True (Test-Path -LiteralPath $newSettings -PathType Leaf) 'missing-settings-are-created'
    Assert-Equal $fakePwsh $newAfter['mcpServers']['openclaw-bridge']['command'] 'missing-settings-use-managed-launcher'
    Assert-True (-not (Test-Path -LiteralPath "$newSettings.openclaw-bridge.bak" -PathType Leaf)) 'missing-settings-have-no-original-file-backup'

    # Invalid JSON must be rejected before either backup or replacement.
    $malformedSettings = Join-Path $testRoot 'malformed\cline_mcp_settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $malformedSettings) -Force | Out-Null
    $malformedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes('{"mcpServers":')
    [System.IO.File]::WriteAllBytes($malformedSettings, $malformedBytes)
    $malformedThrew = $false
    try {
        Invoke-BridgeSetup -SettingsPath $malformedSettings -FakePwsh $fakePwsh -FakeLauncher $fakeLauncher
    }
    catch {
        $malformedThrew = $true
    }
    Assert-True $malformedThrew 'malformed-input-fails'
    Assert-True (Test-ByteEqual $malformedBytes ([System.IO.File]::ReadAllBytes($malformedSettings))) 'malformed-input-leaves-original-bytes-unchanged'
    Assert-True (-not (Test-Path -LiteralPath "$malformedSettings.openclaw-bridge.bak" -PathType Leaf)) 'malformed-input-does-not-create-backup'

    # Missing managed launcher must fail before touching an existing config.
    $missingManagedSettings = Join-Path $testRoot 'missing-managed\cline_mcp_settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $missingManagedSettings) -Force | Out-Null
    [IO.File]::WriteAllText($missingManagedSettings, '{"preserve":true}', [Text.UTF8Encoding]::new($false))
    $missingManagedBytes = [IO.File]::ReadAllBytes($missingManagedSettings)
    $null = & pwsh -NoLogo -NoProfile -NonInteractive -File $setupScript `
        -ClineSettingsPath $missingManagedSettings `
        -ManagedPwshPath (Join-Path $fixtureBin 'missing-pwsh.exe') `
        -ManagedLauncherPath (Join-Path $fixtureBin 'missing-launcher.ps1') `
        -SkipProbe 2>$null
    Assert-True ($LASTEXITCODE -ne 0) 'missing-managed-launcher-fails'
    Assert-True (Test-ByteEqual $missingManagedBytes ([IO.File]::ReadAllBytes($missingManagedSettings))) 'missing-managed-launcher-leaves-config-unchanged'
    Assert-True (-not (Test-Path -LiteralPath "$missingManagedSettings.openclaw-bridge.bak")) 'missing-managed-launcher-creates-no-backup'

    [Console]::WriteLine("PASS=$($script:pass) FAIL=$($script:fail)")
    if ($script:fail -gt 0) { exit 1 }
}
finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedBase = [System.IO.Path]::GetFullPath($tempBase).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $expectedPrefix = $resolvedBase + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
