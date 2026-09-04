#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'api.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('openclaw-api-status-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $fixturePath = Join-Path $tempRoot 'models-status.json'
    $catalogPath = Join-Path $tempRoot 'models-list.json'
    $fixture = [ordered]@{
        defaultModel = 'ollama5090d/qwen3.8:27b'
        fallbacks = @('ollama-cloud/qwen3.5')
        utilityModel = [ordered]@{ ref='openai/gpt-mini'; source='configured' }
        imageModel = $null
        imageFallbacks = @('deepseek/deepseek-chat')
        allowed = @(
            'ollama5090d/qwen3.8:27b'
            'qwen/qwen3.7-plus'
            'deepseek/deepseek-chat'
        )
        auth = [ordered]@{
            providers = @(
                [ordered]@{
                    provider = 'ollama5090d'
                    effective = [ordered]@{ kind = 'models.json' }
                    profiles = [ordered]@{ count = 0 }
                }
                [ordered]@{
                    provider = 'qwen'
                    effective = [ordered]@{ kind = 'profiles' }
                    profiles = [ordered]@{ count = 1; apiKey = 1 }
                }
                [ordered]@{
                    provider = 'deepseek'
                    effective = [ordered]@{ kind = 'profiles' }
                    profiles = [ordered]@{ count = 1; apiKey = 1 }
                }
            )
        }
    }
    [IO.File]::WriteAllText(
        $fixturePath,
        ($fixture | ConvertTo-Json -Depth 12),
        [Text.UTF8Encoding]::new($false)
    )

    $catalog = [ordered]@{
        count = 6
        models = @(
            [ordered]@{ key='ollama5090d/qwen3.8:27b'; local=$true; available=$true }
            [ordered]@{ key='qwen/qwen3.7-plus'; local=$false; available=$true }
            [ordered]@{ key='deepseek/deepseek-chat'; local=$false; available=$true }
            [ordered]@{ key='openai/gpt-mini'; local=$false; available=$true }
            [ordered]@{ key='ollama-cloud/qwen3.5'; local=$false; available=$true }
            [ordered]@{ key='ollama/fixture-local'; local=$true; available=$true }
        )
    }
    [IO.File]::WriteAllText(
        $catalogPath,
        ($catalog | ConvertTo-Json -Depth 12),
        [Text.UTF8Encoding]::new($false)
    )

    $raw = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath status -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath -Json
    if ($LASTEXITCODE -ne 0) { throw "api.ps1 status failed with exit $LASTEXITCODE" }
    $result = $raw | ConvertFrom-Json
    if ($result.schema -ne 'openclaw_gateway.cost_posture.v2') { throw 'Unexpected status schema.' }
    if ($result.default_route -ne 'local') { throw 'Local default route was not detected.' }
    if ($result.remote_route_count -ne 2) { throw 'Remote routes were not counted.' }
    if ($result.remote_auth_provider_count -ne 2) { throw 'Remote auth providers were not counted.' }
    if ($result.utility_route -ne 'remote_or_unknown' -or $result.utility_model -ne 'openai/gpt-mini') {
        throw 'Remote utility model was not reported.'
    }
    if ($result.remote_automatic_route_count -ne 3) {
        throw 'Remote fallback, utility, and image fallback routes were not counted.'
    }
    if (@($result.remote_automatic_routes | Where-Object { $_.model -eq 'ollama-cloud/qwen3.5' }).Count -ne 1) {
        throw 'ollama-cloud was incorrectly classified as local.'
    }
    if ($result.session_and_job_overrides_checked -ne $false) {
        throw 'Status falsely claimed session/job override coverage.'
    }
    if ($result.global_zero_cost_enforced -ne $false) { throw 'Status made a false zero-cost claim.' }
    if ($result.mode_switch_available -ne $false) { throw 'Retired mode switch was reported available.' }

    $fixture.defaultModel = 'ollama-cloud/qwen3.5'
    $fixture.fallbacks = @()
    $fixture.utilityModel = [ordered]@{ ref=$null; source='none' }
    $fixture.imageFallbacks = @()
    $fixture.allowed = @('ollama-cloud/qwen3.5')
    [IO.File]::WriteAllText($fixturePath, ($fixture | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $cloudRaw = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath status -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath -Json
    if ($LASTEXITCODE -ne 0) { throw 'ollama-cloud classification fixture failed.' }
    $cloud = $cloudRaw | ConvertFrom-Json
    if ($cloud.default_route -ne 'remote_or_unknown' -or $cloud.remote_automatic_route_count -ne 1) {
        throw 'ollama-cloud default was falsely classified as local.'
    }

    $fixture.defaultModel = 'ollama5090d/qwen3.8:27b'
    $fixture.allowed = @('ollama5090d/qwen3.8:27b', 'qwen/qwen3.7-plus')
    [IO.File]::WriteAllText($fixturePath, ($fixture | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $localWithRemoteRaw = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath status -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath -Json
    if ($LASTEXITCODE -ne 0) { throw 'Local default with selectable remote fixture failed.' }
    $localWithRemote = $localWithRemoteRaw | ConvertFrom-Json
    if ($localWithRemote.remote_automatic_route_count -ne 0 -or
        $localWithRemote.remote_route_count -ne 1 -or
        $localWithRemote.conclusion -notmatch '远程路线仍可手动选择') {
        throw 'Local automatic route with selectable remote route was misreported.'
    }

    $fixture.allowed = @('ollama5090d/qwen3.8:27b')
    [IO.File]::WriteAllText($fixturePath, ($fixture | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $localOnlyRaw = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath status -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath -Json
    if ($LASTEXITCODE -ne 0) { throw 'Local-only fixture failed.' }
    $localOnly = $localOnlyRaw | ConvertFrom-Json
    if ($localOnly.remote_automatic_route_count -ne 0 -or
        $localOnly.remote_route_count -ne 0 -or
        $localOnly.conclusion -notmatch '当前未列出远程可选路线') {
        throw 'Local-only posture was misreported.'
    }

    $catalog.models += [ordered]@{ key='mystery/model'; available=$true }
    $catalog.count = @($catalog.models).Count
    [IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $fixture.defaultModel = 'mystery/model'
    $fixture.allowed = @('mystery/model')
    [IO.File]::WriteAllText($fixturePath, ($fixture | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $unknownRaw = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath status -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath -Json
    if ($LASTEXITCODE -ne 0) { throw 'Catalog entry without local field crashed status.' }
    $unknown = $unknownRaw | ConvertFrom-Json
    if ($unknown.default_route -ne 'remote_or_unknown') {
        throw 'Catalog entry without explicit local=true was trusted as local.'
    }

    $null = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath off -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath 2>$null
    if ($LASTEXITCODE -ne 2) { throw 'Retired off action must fail with exit 2.' }

    $null = & pwsh -NoLogo -NoProfile -NonInteractive -File $scriptPath on -ModelsStatusPath $fixturePath -ModelsListPath $catalogPath 2>$null
    if ($LASTEXITCODE -ne 2) { throw 'Retired on action must fail with exit 2.' }

    [Console]::WriteLine('PASS cost posture does not misreport remote-capable state as API OFF')
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
