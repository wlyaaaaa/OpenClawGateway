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

    foreach ($name in @('20260726-010101', '20260726-010102', '20260726-010103')) {
        $receipt = Publish-GHotSnapshot -SnapshotPath $source -HotRoot $hot -SnapshotName $name -Keep 2
        if (-not $receipt.readback_verified -or $receipt.file_count -ne 3) {
            throw "Snapshot $name did not return a verified three-file receipt."
        }
    }

    if (Test-Path -LiteralPath (Join-Path $hot '20260726-010101')) {
        throw 'G hot snapshot rotation did not remove the oldest snapshot.'
    }
    $latestManifest = Get-Content -LiteralPath (Join-Path $hot '20260726-010103\.g-hot-snapshot.json') -Raw |
        ConvertFrom-Json
    if ($latestManifest.schema -ne 'ai-memory.g-hot-snapshot.v1' -or
        $latestManifest.file_count -ne 3 -or
        @($latestManifest.files | Where-Object { $_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
        throw 'G hot snapshot manifest is invalid.'
    }
    if ((Get-Content -LiteralPath (Join-Path $hot '20260726-010103\manifest.json') -Raw) -ne
        '{"source":"preserve-me"}') {
        throw 'G hot snapshot receipt overwrote the source-owned manifest.'
    }
    Write-Host 'OK G hot snapshot readback and rotation'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
