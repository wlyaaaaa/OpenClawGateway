$ErrorActionPreference = 'Stop'

function Get-GHotSnapshotInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $resolved = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return @(
        Get-ChildItem -LiteralPath $resolved -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                [PSCustomObject]@{
                    relative_path = $_.FullName.Substring($resolved.Length).TrimStart('\', '/') -replace '\\', '/'
                    length = [int64]$_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
    )
}

function Publish-GHotSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SnapshotPath,

        [Parameter(Mandatory = $true)]
        [string]$HotRoot,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{8}-\d{6}$')]
        [string]$SnapshotName,

        [ValidateRange(1, 365)]
        [int]$Keep = 30
    )

    $source = [IO.Path]::GetFullPath($SnapshotPath).TrimEnd('\', '/')
    $root = [IO.Path]::GetFullPath($HotRoot).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "G hot snapshot source is missing: $source"
    }

    $receiptName = '.g-hot-snapshot.json'
    $sourceInventory = @(Get-GHotSnapshotInventory -Root $source)
    if (@($sourceInventory | Where-Object { $_.relative_path -eq $receiptName }).Count -gt 0) {
        throw "Source snapshot uses the reserved G hot-backup receipt name: $receiptName"
    }
    if ($sourceInventory.Count -eq 0) {
        throw 'G hot snapshot source inventory is empty.'
    }
    $sourceJson = $sourceInventory | ConvertTo-Json -Compress -Depth 5
    $sourceBytes = [int64](($sourceInventory | Measure-Object length -Sum).Sum)

    $latest = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($latest) {
        try {
            $latestManifest = Get-Content -LiteralPath (Join-Path $latest.FullName $receiptName) -Raw |
                ConvertFrom-Json
            $manifestInventory = @(
                $latestManifest.files |
                    Sort-Object relative_path |
                    ForEach-Object {
                        [PSCustomObject]@{
                            relative_path = [string]$_.relative_path
                            length = [int64]$_.length
                            sha256 = [string]$_.sha256
                        }
                    }
            )
            $manifestJson = $manifestInventory | ConvertTo-Json -Compress -Depth 5
            $latestInventory = @(
                Get-GHotSnapshotInventory -Root $latest.FullName |
                    Where-Object { $_.relative_path -ne $receiptName }
            )
            $latestJson = $latestInventory | ConvertTo-Json -Compress -Depth 5
            if ($latestManifest.schema -eq 'ai-memory.g-hot-snapshot.v1' -and
                [int]$latestManifest.file_count -eq $sourceInventory.Count -and
                [int64]$latestManifest.total_size_bytes -eq $sourceBytes -and
                $manifestJson -ceq $sourceJson -and
                $latestJson -ceq $sourceJson) {
                return [PSCustomObject]@{
                    destination = [IO.Path]::GetFullPath($latest.FullName)
                    file_count = $sourceInventory.Count
                    total_size_bytes = $sourceBytes
                    readback_verified = $true
                    skipped_identical = $true
                }
            }
        } catch {
            # Never trust an invalid latest snapshot as a duplicate. The normal
            # verified publication path below remains the fail-safe fallback.
        }
    }

    $destination = Join-Path $root $SnapshotName
    $destinationFull = [IO.Path]::GetFullPath($destination)
    if (-not $destinationFull.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "G hot snapshot destination escaped its root: $destinationFull"
    }
    if (Test-Path -LiteralPath $destinationFull) {
        throw "G hot snapshot destination already exists: $destinationFull"
    }

    $null = New-Item -ItemType Directory -Path $destinationFull -Force
    try {
        Get-ChildItem -LiteralPath $source -Force |
            Copy-Item -Destination $destinationFull -Recurse -Force

        $destinationInventory = @(Get-GHotSnapshotInventory -Root $destinationFull)
        $destinationJson = $destinationInventory | ConvertTo-Json -Compress -Depth 5
        if ($sourceJson -cne $destinationJson) {
            throw 'G hot snapshot readback inventory does not match the source snapshot.'
        }

        $manifest = [ordered]@{
            schema = 'ai-memory.g-hot-snapshot.v1'
            completed_utc = [DateTimeOffset]::UtcNow.ToString('o')
            snapshot_name = $SnapshotName
            file_count = $sourceInventory.Count
            total_size_bytes = $sourceBytes
            files = $sourceInventory
        }
        [IO.File]::WriteAllText(
            (Join-Path $destinationFull $receiptName),
            ($manifest | ConvertTo-Json -Depth 8),
            [Text.UTF8Encoding]::new($false)
        )
        $postReceiptInventory = @(
            Get-GHotSnapshotInventory -Root $destinationFull |
                Where-Object { $_.relative_path -ne $receiptName }
        )
        $postReceiptJson = $postReceiptInventory | ConvertTo-Json -Compress -Depth 5
        if ($sourceJson -cne $postReceiptJson) {
            throw 'G hot snapshot changed after writing its separate readback receipt.'
        }
    } catch {
        if (Test-Path -LiteralPath $destinationFull) {
            Remove-Item -LiteralPath $destinationFull -Recurse -Force
        }
        throw
    }

    $snapshots = @(
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
            Sort-Object Name -Descending
    )
    if ($snapshots.Count -gt $Keep) {
        foreach ($old in @($snapshots | Select-Object -Skip $Keep)) {
            $oldFull = [IO.Path]::GetFullPath($old.FullName)
            if (-not $oldFull.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to rotate a G hot snapshot outside its root: $oldFull"
            }
            Remove-Item -LiteralPath $oldFull -Recurse -Force
        }
    }

    return [PSCustomObject]@{
        destination = $destinationFull
        file_count = $sourceInventory.Count
        total_size_bytes = $sourceBytes
        readback_verified = $true
        skipped_identical = $false
    }
}
