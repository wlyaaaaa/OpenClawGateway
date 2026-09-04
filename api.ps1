<#
.SYNOPSIS
  查看 OpenClaw 的模型成本态势；不修改凭据或运行状态。
.DESCRIPTION
  旧版 on/off/toggle 只检查一个过期的 openai:default 文件记录，无法覆盖
  OpenClaw 2.0 的 SQLite、环境变量和 Provider 路由，因此已经退役。

  status 会读取官方 `openclaw models status --json` 结果，分别报告：
    - 当前默认模型是不是本地路线；
    - 仍可选择的远程模型路线；
    - OpenClaw 是否仍能看到远程认证来源。

  这是一份只读诊断，不把“默认本地模型”冒充成全局零费用保证。
.EXAMPLE
  .\api.ps1 status
.EXAMPLE
  .\api.ps1 status -Json
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'on', 'off', 'toggle', '')]
    [string]$Action = 'status',

    [string]$ModelsStatusPath,

    [string]$ModelsListPath,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProfileCount($ProviderStatus) {
    if ($null -eq $ProviderStatus -or $null -eq $ProviderStatus.profiles) { return 0 }
    $count = $ProviderStatus.profiles.PSObject.Properties['count']
    if ($null -eq $count) { return 0 }
    return [int]$count.Value
}

function Get-ModelRef($Value) {
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return [string]$Value }
    $ref = $Value.PSObject.Properties['ref']
    if ($null -ne $ref) { return [string]$ref.Value }
    $primary = $Value.PSObject.Properties['primary']
    if ($null -ne $primary) { return [string]$primary.Value }
    return ''
}

function Get-RouteClass([string]$ModelRef) {
    if ([string]::IsNullOrWhiteSpace($ModelRef)) { return 'unset' }
    if ($ModelRef.EndsWith('/*')) {
        $provider = $ModelRef.Substring(0, $ModelRef.Length - 2)
        if (Test-ProviderCatalogLocal $provider) { return 'local' }
        return 'remote_or_unknown'
    }
    $entry = @($script:CatalogModels | Where-Object { [string]$_.key -ceq $ModelRef }) | Select-Object -First 1
    if (Test-CatalogEntryLocal $entry) { return 'local' }
    return 'remote_or_unknown'
}

function Test-CatalogEntryLocal($Entry) {
    if ($null -eq $Entry) { return $false }
    $local = $Entry.PSObject.Properties['local']
    return $null -ne $local -and $local.Value -eq $true
}

function Test-ProviderCatalogLocal([string]$Provider) {
    if ([string]::IsNullOrWhiteSpace($Provider)) { return $false }
    $entries = @($script:CatalogModels | Where-Object { [string]$_.key -like "$Provider/*" })
    return $entries.Count -gt 0 -and @($entries | Where-Object { -not (Test-CatalogEntryLocal $_) }).Count -eq 0
}

function Read-ModelsStatus {
    if (-not [string]::IsNullOrWhiteSpace($ModelsStatusPath)) {
        return Get-Content -LiteralPath $ModelsStatusPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 40
    }

    $raw = & openclaw models status --json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'openclaw models status --json failed.' }
    return $raw | ConvertFrom-Json -Depth 40
}

function Read-ModelsList {
    if (-not [string]::IsNullOrWhiteSpace($ModelsListPath)) {
        $result = Get-Content -LiteralPath $ModelsListPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 40
    }
    else {
        $raw = & openclaw models list --json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'openclaw models list --json failed.' }
        $result = $raw | ConvertFrom-Json -Depth 40
    }
    if ($null -eq $result.PSObject.Properties['models'] -or @($result.models).Count -eq 0) {
        throw 'openclaw models list --json returned no model catalog.'
    }
    return $result
}

if ($Action -in @('on', 'off', 'toggle', '')) {
    [Console]::Error.WriteLine(
        '旧版 API 开关已退役：它无法证明 OpenClaw 2.0 的所有远程凭据和会话模型都已关闭。' +
        '请使用 api.ps1 status 查看当前成本态势，并通过 OpenClaw 官方 models/config 命令做明确变更。'
    )
    exit 2
}

$models = Read-ModelsStatus
$catalog = Read-ModelsList
$script:CatalogModels = @($catalog.models)
$defaultModel = [string]$models.defaultModel
$defaultRoute = Get-RouteClass $defaultModel

$allowed = @($models.allowed | ForEach-Object { [string]$_ } | Where-Object { $_ })
$remoteRoutes = @(
    $allowed |
        Where-Object {
            (Get-RouteClass $_) -ne 'local'
        } |
        Sort-Object -Unique
)
$remoteProviders = @(
    $remoteRoutes |
        ForEach-Object { ($_ -split '/', 2)[0] } |
        Sort-Object -Unique
)

$remoteAuthProviders = @(
    @($models.auth.providers) |
        Where-Object {
            $provider = [string]$_.provider
            $effectiveKind = [string]$_.effective.kind
            -not (Test-ProviderCatalogLocal $provider) -and
                ((Get-ProfileCount $_) -gt 0 -or
                 $effectiveKind -in @('env', 'profiles', 'oauth', 'token', 'api_key'))
        } |
        ForEach-Object { [string]$_.provider } |
        Sort-Object -Unique
)

$utilityModel = Get-ModelRef $models.utilityModel
$imageModel = Get-ModelRef $models.imageModel
$automaticRoutes = [Collections.Generic.List[object]]::new()
if ($defaultModel) {
    $automaticRoutes.Add([pscustomobject]@{ kind='default'; model=$defaultModel; route=(Get-RouteClass $defaultModel) })
}
foreach ($fallback in @($models.fallbacks)) {
    $ref = Get-ModelRef $fallback
    if ($ref) { $automaticRoutes.Add([pscustomobject]@{ kind='fallback'; model=$ref; route=(Get-RouteClass $ref) }) }
}
if ($utilityModel) {
    $automaticRoutes.Add([pscustomobject]@{ kind='utility'; model=$utilityModel; route=(Get-RouteClass $utilityModel) })
}
if ($imageModel) {
    $automaticRoutes.Add([pscustomobject]@{ kind='image'; model=$imageModel; route=(Get-RouteClass $imageModel) })
}
foreach ($fallback in @($models.imageFallbacks)) {
    $ref = Get-ModelRef $fallback
    if ($ref) { $automaticRoutes.Add([pscustomobject]@{ kind='image_fallback'; model=$ref; route=(Get-RouteClass $ref) }) }
}
$remoteAutomaticRoutes = @($automaticRoutes | Where-Object { $_.route -eq 'remote_or_unknown' })

$result = [ordered]@{
    schema = 'openclaw_gateway.cost_posture.v2'
    default_model = $defaultModel
    default_route = $defaultRoute
    utility_model = $(if ($utilityModel) { $utilityModel } else { $null })
    utility_route = Get-RouteClass $utilityModel
    image_model = $(if ($imageModel) { $imageModel } else { $null })
    image_route = Get-RouteClass $imageModel
    automatic_routes = @($automaticRoutes)
    remote_automatic_route_count = $remoteAutomaticRoutes.Count
    remote_automatic_routes = $remoteAutomaticRoutes
    remote_route_count = $remoteRoutes.Count
    remote_providers = $remoteProviders
    remote_auth_provider_count = $remoteAuthProviders.Count
    remote_auth_providers = $remoteAuthProviders
    global_zero_cost_enforced = $false
    mode_switch_available = $false
    session_and_job_overrides_checked = $false
    conclusion = $(
        if ($remoteAutomaticRoutes.Count -gt 0) {
            '至少一条默认、回退、utility 或图像路线不是本地 Provider；可能自动产生远程模型费用。'
        }
        elseif ($defaultRoute -eq 'local' -and $remoteRoutes.Count -eq 0) {
            '已列出的自动路线均为本地或未配置，且当前未列出远程可选路线；仍未核对逐会话和计划任务覆盖。'
        }
        elseif ($defaultRoute -eq 'local') {
            '已列出的自动路线均为本地或未配置，但远程路线仍可手动选择；不能称为全局零费用模式。'
        }
        else {
            '默认路线不是已识别的本地 Provider；可能产生远程模型费用。'
        }
    )
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

Write-Host ''
Write-Host 'OpenClaw 模型成本态势' -ForegroundColor Green
Write-Host ("  默认模型        {0}" -f $(if ($defaultModel) { $defaultModel } else { '未配置' }))
Write-Host ("  默认路线        {0}" -f $result.default_route)
Write-Host ("  utility 模型   {0}（{1}）" -f $(if ($utilityModel) { $utilityModel } else { '未配置' }), $result.utility_route)
Write-Host ("  图像模型        {0}（{1}）" -f $(if ($imageModel) { $imageModel } else { '未配置' }), $result.image_route)
Write-Host ("  自动远程路线    {0}" -f $result.remote_automatic_route_count)
Write-Host ("  远程模型路线    {0}（Provider: {1}）" -f $result.remote_route_count, $(if ($remoteProviders.Count) { $remoteProviders -join ', ' } else { '无' }))
Write-Host ("  远程认证来源    {0}（Provider: {1}）" -f $result.remote_auth_provider_count, $(if ($remoteAuthProviders.Count) { $remoteAuthProviders -join ', ' } else { '无' }))
Write-Host '  全局零费用保证  未启用；本脚本只读，不改凭据、会话或网关。' -ForegroundColor Yellow
Write-Host ("  结论            {0}" -f $result.conclusion)
Write-Host ''
