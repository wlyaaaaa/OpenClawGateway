[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Path $PSScriptRoot -Parent
$bootstrap = Join-Path $repo 'bootstrap'
$setup = Join-Path $bootstrap 'setup.ps1'
$templatePath = Join-Path $bootstrap 'openclaw.template.json'

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "断言失败：$Message"
    }
}

function Get-LeafString {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Value -is [string]) {
        [pscustomobject]@{ Path = $Path; Value = $Value }
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Value) {
            Get-LeafString -Value $item -Path "$Path[$index]"
            $index++
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            Get-LeafString -Value $property.Value -Path "$Path.$($property.Name)"
        }
    }
}

$templateRaw = Get-Content -LiteralPath $templatePath -Raw -Encoding utf8
$template = $templateRaw | ConvertFrom-Json -Depth 100
$setupRaw = Get-Content -LiteralPath $setup -Raw -Encoding utf8

Assert-Condition ($template.agents.defaults.workspace -eq '__REPLACE_WITH_WORKSPACE_PATH__') 'workspace 必须是明确占位符。'
Assert-Condition ($template.agents.defaults.model.primary -eq '__REPLACE_WITH_MODEL_ID__') '默认模型必须是明确占位符。'
Assert-Condition ($template.agents.defaults.heartbeat.model -eq '__REPLACE_WITH_MODEL_ID__') 'heartbeat 模型必须是明确占位符。'

$forbiddenMachineValue = '(?i)(?:https?://|[a-z]:\\|\\\\users\\|@)'
foreach ($leaf in @(Get-LeafString -Value $template -Path '$')) {
    Assert-Condition ($leaf.Value -notmatch $forbiddenMachineValue) "模板不能包含机器、账号或网络值：$($leaf.Path)。"
}
Assert-Condition ($templateRaw -notmatch '\*') '模板不能包含通配符 allowlist。'

$channels = @($template.channels.PSObject.Properties)
Assert-Condition ($channels.Count -gt 0) '模板必须显式包含消息渠道。'
foreach ($channel in $channels) {
    Assert-Condition ($channel.Value.enabled -eq $false) "渠道 $($channel.Name) 必须默认关闭。"
}
foreach ($channelName in @('feishu', 'telegram')) {
    foreach ($allowProperty in @('allowFrom', 'groupAllowFrom')) {
        $allowList = $template.channels.$channelName.$allowProperty
        Assert-Condition ($allowList -is [System.Collections.IEnumerable] -and $allowList -isnot [string]) "$channelName.$allowProperty 必须是列表。"
        Assert-Condition (@($allowList).Count -eq 0) "$channelName.$allowProperty 必须为空。"
    }
}

Assert-Condition ($template.plugins.entries.'memory-core'.config.dreaming.enabled -eq $false) 'dreaming 必须默认关闭。'
Assert-Condition ($template.update.auto.enabled -eq $false) '自动更新必须默认关闭。'
Assert-Condition ($template.update.checkOnStart -eq $false) '启动检查更新必须默认关闭。'
Assert-Condition ($template.gateway.bind -eq 'loopback') '网关必须绑定 loopback。'
Assert-Condition ($null -eq $template.gateway.PSObject.Properties['auth']) '公共模板不得预设私人 Gateway 认证方式。'

Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $bootstrap 'auth-profiles.template.json'))) '旧 auth-profiles 模板必须退役。'
foreach ($retiredToken in @('RestoreFrom', 'SetGatewayPassword', 'GatewayPassword', 'auth-profiles.json', 'OPENCLAW_GATEWAY_PASSWORD')) {
    Assert-Condition ($setupRaw -notmatch [regex]::Escape($retiredToken)) "setup 不能保留旧凭据层：$retiredToken。"
}
Assert-Condition ($setupRaw -match 'openclaw models auth') 'setup 必须指向官方模型认证入口。'
Assert-Condition ($setupRaw -match 'tools/restore-config\.ps1') 'setup 必须指向新的恢复入口。'
Assert-Condition ($setupRaw -match [regex]::Escape("-ArgumentList @('-Repair')")) '注册网关必须显式调用 guardian -Repair。'

$preflightOutput = @(& pwsh -NoProfile -File $setup -ConfigSource $templatePath -WhatIf 2>&1)
$preflightExitCode = $LASTEXITCODE
Assert-Condition ($preflightExitCode -ne 0) '未填占位符必须使 setup 非零退出。'
Assert-Condition (($preflightOutput -join [Environment]::NewLine) -match '必填占位符') 'setup 必须说明占位符预检失败。'

. $setup -LibraryOnly
$observedEffects = [System.Collections.Generic.List[string]]::new()
$preflightError = $null
try {
    Start-OpenClawBootstrap -ConfigSource $templatePath -WhatIf -EffectObserver {
        param([string]$Name)
        $observedEffects.Add($Name)
    }
}
catch {
    $preflightError = $_
}
Assert-Condition ($null -ne $preflightError) '占位符预检必须在库入口中失败。'
Assert-Condition ($observedEffects.Count -eq 0) '占位符预检失败前不得计划任何副作用。'

$tempRoot = if ([string]::IsNullOrWhiteSpace($env:OPENCLAW_TEST_TEMP_ROOT)) {
    [IO.Path]::GetTempPath()
}
else {
    $env:OPENCLAW_TEST_TEMP_ROOT
}
$scratch = Join-Path $tempRoot ("openclaw-bootstrap-test-" + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $filledConfig = Join-Path $scratch 'openclaw.json'
    $filledTemplate = $templateRaw.Replace('__REPLACE_WITH_WORKSPACE_PATH__', 'C:\\OpenClawWorkspace').Replace('__REPLACE_WITH_MODEL_ID__', 'example/model')
    [System.IO.File]::WriteAllText($filledConfig, $filledTemplate, [System.Text.UTF8Encoding]::new($false))

    $oldConfigPath = $env:OPENCLAW_CONFIG_PATH
    try {
        $env:OPENCLAW_CONFIG_PATH = $filledConfig
        $schemaRaw = & openclaw config validate --json 2>$null
        $schemaExit = $LASTEXITCODE
    }
    finally {
        [Environment]::SetEnvironmentVariable('OPENCLAW_CONFIG_PATH', $oldConfigPath, 'Process')
    }
    Assert-Condition ($schemaExit -eq 0) '填完占位符的公共模板必须通过当前 OpenClaw schema 校验。'
    $schemaResult = $schemaRaw | ConvertFrom-Json
    Assert-Condition ($schemaResult.valid -eq $true) 'OpenClaw schema 回读必须明确 valid=true。'

    $criticalError = $null
    try {
        Start-OpenClawBootstrap -ConfigSource $filledConfig -WhatIf -CommandInvoker {
            param([string]$FilePath, [string[]]$ArgumentList)
            return 73
        }
    }
    catch {
        $criticalError = $_
    }

    Assert-Condition ($null -ne $criticalError) '关键外部命令失败必须向上传播。'
    Assert-Condition ($criticalError.Exception.Message -match '退出码：73') '关键外部命令失败必须保留退出码。'

    $schemaEffects = [System.Collections.Generic.List[string]]::new()
    $schemaError = $null
    try {
        Start-OpenClawBootstrap -ConfigSource $filledConfig -WhatIf -EffectObserver {
            param([string]$Name)
            $schemaEffects.Add($Name)
        } -CommandInvoker {
            param([string]$FilePath, [string[]]$ArgumentList)
            if ($ArgumentList.Count -ge 2 -and
                $ArgumentList[0] -eq 'config' -and
                $ArgumentList[1] -eq 'validate') {
                return 73
            }
            return 0
        }
    }
    catch {
        $schemaError = $_
    }
    Assert-Condition ($null -ne $schemaError) '候选 schema 校验失败必须向上传播。'
    Assert-Condition ($schemaEffects.Count -eq 0) '候选 schema 校验必须早于配置写入副作用。'

    $fakeBin = Join-Path $scratch 'fake-bin'
    $schemaMarker = Join-Path $scratch 'schema-marker.txt'
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    $fakeOpenClaw = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
if ($Arguments.Count -ge 2 -and $Arguments[0] -eq 'config' -and $Arguments[1] -eq 'validate') {
    [IO.File]::AppendAllText($env:OPENCLAW_BOOTSTRAP_SCHEMA_MARKER, "validated`n", [Text.UTF8Encoding]::new($false))
}
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $fakeBin 'openclaw.ps1'), $fakeOpenClaw, [Text.UTF8Encoding]::new($false))
    $oldPath = $env:PATH
    $oldMarker = $env:OPENCLAW_BOOTSTRAP_SCHEMA_MARKER
    try {
        $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath
        $env:OPENCLAW_BOOTSTRAP_SCHEMA_MARKER = $schemaMarker
        Start-OpenClawBootstrap -ConfigSource $filledConfig -WhatIf
    }
    finally {
        $env:PATH = $oldPath
        [Environment]::SetEnvironmentVariable('OPENCLAW_BOOTSTRAP_SCHEMA_MARKER', $oldMarker, 'Process')
    }
    Assert-Condition (Test-Path -LiteralPath $schemaMarker -PathType Leaf) 'WhatIf 必须真实运行只读候选 schema 校验。'
    Assert-Condition (@(Get-Content -LiteralPath $schemaMarker).Count -eq 1) 'WhatIf 只能校验候选配置，不能假装校验未写入的生效配置。'

    $transactionSource = Join-Path $scratch 'candidate.json'
    $transactionDestination = Join-Path $scratch 'active\openclaw.json'
    [IO.File]::WriteAllText($transactionSource, '{"value":"new"}', [Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path (Split-Path -Parent $transactionDestination) -Force | Out-Null
    [IO.File]::WriteAllText($transactionDestination, '{"value":"old"}', [Text.UTF8Encoding]::new($false))
    $transaction = Install-BootstrapConfigAtomically -Source $transactionSource -Destination $transactionDestination
    Assert-Condition (([IO.File]::ReadAllText($transactionDestination) | ConvertFrom-Json).value -eq 'new') '原子安装必须激活候选配置。'
    Restore-BootstrapConfigTransaction -Transaction $transaction
    Assert-Condition (([IO.File]::ReadAllText($transactionDestination) | ConvertFrom-Json).value -eq 'old') '后验失败回滚必须恢复原配置。'
}
finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}

Write-Host 'Bootstrap policy tests passed.' -ForegroundColor Green
