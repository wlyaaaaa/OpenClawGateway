<#
.SYNOPSIS
  安全地安装并配置 OpenClaw 网关。

.DESCRIPTION
  公共模板只包含占位符。将其复制到受信任的私有位置并替换全部
  __REPLACE_WITH_*__ 值后，把已填完的配置副本传给 -ConfigSource。
  预检失败时，本脚本不会安装软件、写入配置、注册或启动网关。

  模型认证请使用官方 openclaw models auth。恢复请走
  tools/restore-config.ps1 的全新暂存合同，而不是向本脚本传入恢复目录。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigSource,
    [switch]$RegisterGateway,
    [Parameter(DontShow)]
    [switch]$LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Path $PSScriptRoot -Parent
$script:BootstrapWhatIf = $false

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor DarkGray
}

function Get-RequiredPlaceholderPath {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Value -is [string]) {
        if ($Value -match '^__REPLACE_WITH_[A-Z0-9_]+__$') {
            Write-Output $Path
        }
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Value) {
            Get-RequiredPlaceholderPath -Value $item -Path "$Path[$index]"
            $index++
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            Get-RequiredPlaceholderPath -Value $property.Value -Path "$Path.$($property.Name)"
        }
    }
}

function Read-BootstrapJson {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Bootstrap JSON 无法解析：$([System.IO.Path]::GetFileName($Path))。$($_.Exception.Message)"
    }
}

function Test-BootstrapConfig {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ConfigSource)

    if ([string]::IsNullOrWhiteSpace($ConfigSource) -or -not (Test-Path -LiteralPath $ConfigSource -PathType Leaf)) {
        throw 'ConfigSource 必须是已填完的私有 openclaw 配置文件。'
    }

    $sourcePath = (Resolve-Path -LiteralPath $ConfigSource).Path
    $json = Read-BootstrapJson -Path $sourcePath
    $placeholderPaths = @(Get-RequiredPlaceholderPath -Value $json -Path '$')
    if ($placeholderPaths.Count -gt 0) {
        throw "ConfigSource 仍含必填占位符。请在私有副本中替换后重试：$($placeholderPaths -join ', ')。"
    }

    return $sourcePath
}

function Invoke-CriticalExternal {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [scriptblock]$CommandInvoker,
        [switch]$RunDuringWhatIf
    )

    if ($CommandInvoker) {
        $result = @(& $CommandInvoker $FilePath $ArgumentList)
        if ($result.Count -ne 1 -or $result[0] -isnot [int]) {
            throw "$Name 的测试命令注入器必须返回一个整数退出码。"
        }

        if ([int]$result[0] -ne 0) {
            throw "$Name 失败，退出码：$($result[0])。"
        }

        if ($script:BootstrapWhatIf) {
            Write-Info "[WhatIf] 已模拟：$Name"
        }
        return
    }

    if ($script:BootstrapWhatIf -and -not $RunDuringWhatIf) {
        Write-Info "[WhatIf] 将执行：$Name"
        return
    }

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Name 失败，退出码：$exitCode。"
    }
}

function Invoke-BootstrapEffect {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [scriptblock]$EffectObserver
    )

    if ($EffectObserver) {
        & $EffectObserver $Name
    }

    if ($script:BootstrapWhatIf) {
        Write-Info "[WhatIf] 将执行副作用：$Name"
        return
    }

    & $Action
}

function Install-BootstrapConfigAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourceFull = [IO.Path]::GetFullPath($Source)
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    if ($sourceFull -ieq $destinationFull) {
        throw 'ConfigSource 不能直接指向正在使用的 openclaw.json。'
    }

    $directory = Split-Path -Parent $destinationFull
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $candidate = Join-Path $directory ('.openclaw-bootstrap-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $hadOriginal = Test-Path -LiteralPath $destinationFull -PathType Leaf
    $rollback = if ($hadOriginal) {
        Join-Path $directory ('openclaw.pre-bootstrap-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N') + '.json')
    }
    else { $null }

    try {
        [IO.File]::Copy($sourceFull, $candidate, $true)
        $null = Read-BootstrapJson -Path $candidate
        if ($hadOriginal) {
            [IO.File]::Replace($candidate, $destinationFull, $rollback, $true)
        }
        else {
            [IO.File]::Move($candidate, $destinationFull)
        }
    }
    finally {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Remove-Item -LiteralPath $candidate -Force
        }
    }

    return [pscustomobject]@{
        Destination = $destinationFull
        HadOriginal = $hadOriginal
        Rollback = $rollback
    }
}

function Restore-BootstrapConfigTransaction {
    param([Parameter(Mandatory)]$Transaction)

    if ($Transaction.HadOriginal -and
        (Test-Path -LiteralPath $Transaction.Rollback -PathType Leaf)) {
        Copy-Item -LiteralPath $Transaction.Rollback -Destination $Transaction.Destination -Force
    }
    elseif (-not $Transaction.HadOriginal -and
        (Test-Path -LiteralPath $Transaction.Destination -PathType Leaf)) {
        Remove-Item -LiteralPath $Transaction.Destination -Force
    }
}

function Test-Administrator {
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw '注册网关需要管理员 PowerShell。'
    }
}

function Start-OpenClawBootstrap {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ConfigSource,
        [switch]$RegisterGateway,
        [Parameter(DontShow)]
        [scriptblock]$EffectObserver,
        [Parameter(DontShow)]
        [scriptblock]$CommandInvoker
    )

    $previousWhatIf = $script:BootstrapWhatIf
    $script:BootstrapWhatIf = [bool]$WhatIfPreference
    try {
        # 必须是第一个会影响机器状态的步骤之前的预检。
        $sourcePath = Test-BootstrapConfig -ConfigSource $ConfigSource

        Write-Step '检查运行时'
        if (-not (Get-Command -Name node -ErrorAction SilentlyContinue)) {
            Invoke-CriticalExternal -Name 'Node.js 安装' -FilePath 'winget' -ArgumentList @(
                'install', '-e', '--id', 'OpenJS.NodeJS.LTS',
                '--accept-source-agreements', '--accept-package-agreements'
            ) -CommandInvoker $CommandInvoker
        }
        if (-not (Get-Command -Name openclaw -ErrorAction SilentlyContinue)) {
            Invoke-CriticalExternal -Name 'OpenClaw 安装' -FilePath 'npm' -ArgumentList @(
                'install', '-g', 'openclaw'
            ) -CommandInvoker $CommandInvoker
        }
        Invoke-CriticalExternal -Name 'OpenClaw 版本检查' -FilePath 'openclaw' -ArgumentList @('--version') -CommandInvoker $CommandInvoker -RunDuringWhatIf

        $previousConfigPath = $env:OPENCLAW_CONFIG_PATH
        try {
            $env:OPENCLAW_CONFIG_PATH = $sourcePath
            Invoke-CriticalExternal -Name '候选 OpenClaw 配置校验' -FilePath 'openclaw' -ArgumentList @(
                'config', 'validate', '--json'
            ) -CommandInvoker $CommandInvoker -RunDuringWhatIf
        }
        finally {
            if ($null -eq $previousConfigPath) {
                [Environment]::SetEnvironmentVariable('OPENCLAW_CONFIG_PATH', $null, 'Process')
            }
            else {
                [Environment]::SetEnvironmentVariable('OPENCLAW_CONFIG_PATH', $previousConfigPath, 'Process')
            }
        }

        Write-Step '写入已预检的配置'
        $configRoot = Join-Path $env:USERPROFILE '.openclaw'
        $destinationPath = Join-Path $configRoot 'openclaw.json'
        $transaction = Invoke-BootstrapEffect -Name '写入 openclaw.json' -EffectObserver $EffectObserver -Action {
            Install-BootstrapConfigAtomically -Source $sourcePath -Destination $destinationPath
        }
        try {
            Invoke-CriticalExternal -Name '生效 OpenClaw 配置校验' -FilePath 'openclaw' -ArgumentList @(
                'config', 'validate', '--json'
            ) -CommandInvoker $CommandInvoker
        }
        catch {
            if (-not $script:BootstrapWhatIf -and $null -ne $transaction) {
                Restore-BootstrapConfigTransaction -Transaction $transaction
            }
            throw
        }
        if (-not $script:BootstrapWhatIf -and $null -ne $transaction -and $transaction.Rollback) {
            Write-Info "原配置回退副本：$($transaction.Rollback)"
        }

        if ($RegisterGateway) {
            Test-Administrator
            $guardian = Join-Path $repo 'openclaw_silent_boot_guardian.ps1'
            if (-not (Test-Path -LiteralPath $guardian -PathType Leaf)) {
                throw '未找到网关注册入口。'
            }

            Write-Step '注册网关'
            Invoke-CriticalExternal -Name '网关注册修复' -FilePath $guardian -ArgumentList @('-Repair') -CommandInvoker $CommandInvoker
        }

        if ($script:BootstrapWhatIf) {
            Write-Info 'WhatIf 预演完成；没有安装、写入、注册或启动任何组件。'
        }
        else {
            Write-Host 'OpenClaw bootstrap 已完成。' -ForegroundColor Green
        }
    }
    finally {
        $script:BootstrapWhatIf = $previousWhatIf
    }
}

if ($LibraryOnly) {
    return
}

if ([string]::IsNullOrWhiteSpace($ConfigSource)) {
    Write-Error '必须通过 -ConfigSource 提供已填完的私有 openclaw 配置文件。'
    exit 1
}

try {
    Start-OpenClawBootstrap -ConfigSource $ConfigSource -RegisterGateway:$RegisterGateway -WhatIf:$WhatIfPreference
}
catch {
    Write-Error $_
    exit 1
}
