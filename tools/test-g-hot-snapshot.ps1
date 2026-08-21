$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'g-hot-snapshot.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("g-hot-snapshot-test-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$source = Join-Path $tempRoot 'source'
$hot = Join-Path $tempRoot 'hot'
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force
    [IO.File]::WriteAllText((Join-Path $source 'one.txt'), "one`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'nested\two.txt'), "two`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'manifest.json'), '{"source":"preserve-me"}', [Text.UTF8Encoding]::new($false))

    $first = Publish-GHotSnapshot -SnapshotPath $source -HotRoot $hot -SnapshotName '20260726-010101' -Keep 2
    if (-not $first.readback_verified -or $first.file_count -ne 3 -or $first.skipped_identical) {
        throw 'Initial snapshot did not return a verified three-file receipt.'
    }

    $duplicate = Publish-GHotSnapshot -SnapshotPath $source -HotRoot $hot -SnapshotName '20260726-010102' -Keep 2
    if (-not $duplicate.readback_verified -or -not $duplicate.skipped_identical -or
        $duplicate.destination -cne $first.destination -or
        (Test-Path -LiteralPath (Join-Path $hot '20260726-010102'))) {
        throw 'Identical source created a redundant timestamped snapshot.'
    }

    [IO.File]::WriteAllText((Join-Path $source 'nested\two.txt'), "two changed`n", [Text.UTF8Encoding]::new($false))
    $second = Publish-GHotSnapshot -SnapshotPath $source -HotRoot $hot -SnapshotName '20260726-010103' -Keep 2
    if (-not $second.readback_verified -or $second.skipped_identical) {
        throw 'Changed source did not create a new verified snapshot.'
    }

    [IO.File]::WriteAllText((Join-Path $source 'one.txt'), "one changed`n", [Text.UTF8Encoding]::new($false))
    $third = Publish-GHotSnapshot -SnapshotPath $source -HotRoot $hot -SnapshotName '20260726-010104' -Keep 2
    if (-not $third.readback_verified -or $third.skipped_identical) {
        throw 'Second changed source did not create a new verified snapshot.'
    }

    if (Test-Path -LiteralPath (Join-Path $hot '20260726-010101')) {
        throw 'G hot snapshot rotation did not remove the oldest snapshot.'
    }
    $latestManifest = Get-Content -LiteralPath (Join-Path $hot '20260726-010104\.g-hot-snapshot.json') -Raw |
        ConvertFrom-Json
    if ($latestManifest.schema -ne 'ai-memory.g-hot-snapshot.v1' -or
        $latestManifest.file_count -ne 3 -or
        @($latestManifest.files | Where-Object { $_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
        throw 'G hot snapshot manifest is invalid.'
    }
    if ((Get-Content -LiteralPath (Join-Path $hot '20260726-010104\manifest.json') -Raw) -ne
        '{"source":"preserve-me"}') {
        throw 'G hot snapshot receipt overwrote the source-owned manifest.'
    }
    Write-Host 'OK G hot snapshot readback and rotation'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
