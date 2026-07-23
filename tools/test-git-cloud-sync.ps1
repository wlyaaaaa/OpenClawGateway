param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'git-cloud-sync.ps1')

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("openclaw-git-sync-test-{0}-{1}" -f $PID, ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function Invoke-TestGit([string]$repo, [string[]]$arguments) {
    Invoke-GitCapture -Repository $repo -Arguments $arguments | Out-Null
}

function Configure-Identity([string]$repo) {
    Invoke-TestGit $repo @('config', 'user.name', 'Backup Test')
    Invoke-TestGit $repo @('config', 'user.email', 'backup-test@example.invalid')
}

function Add-TestCommit([string]$repo, [string]$name, [string]$content) {
    $path = Join-Path $repo $name
    $content | Set-Content -LiteralPath $path -Encoding utf8
    Invoke-TestGit $repo @('add', '--', $name)
    Invoke-TestGit $repo @('commit', '-m', "test $name")
}

function New-BareTopology([string]$name) {
    $base = Join-Path $testRoot $name
    $seed = Join-Path $base 'seed'
    $remote = Join-Path $base 'remote.git'
    $local = Join-Path $base 'local'
    $peer = Join-Path $base 'peer'
    New-Item -ItemType Directory -Path $seed -Force | Out-Null
    Invoke-TestGit $seed @('init', '--quiet')
    Configure-Identity $seed
    Add-TestCommit $seed 'seed.txt' 'seed'
    Invoke-TestGit $seed @('branch', '-M', 'main')
    Invoke-TestGit $seed @('init', '--bare', '--quiet', $remote)
    Invoke-TestGit $seed @('remote', 'add', 'origin', $remote)
    Invoke-TestGit $seed @('push', '--quiet', '-u', 'origin', 'main')
    Invoke-TestGit $remote @('symbolic-ref', 'HEAD', 'refs/heads/main')
    Invoke-TestGit $base @('clone', '--quiet', $remote, $local)
    Invoke-TestGit $base @('clone', '--quiet', $remote, $peer)
    Configure-Identity $local
    Configure-Identity $peer
    [PSCustomObject]@{ Base = $base; Remote = $remote; Local = $local; Peer = $peer }
}

function New-NonBareTopology([string]$name) {
    $base = Join-Path $testRoot $name
    $remote = Join-Path $base 'remote'
    $local = Join-Path $base 'local'
    New-Item -ItemType Directory -Path $remote -Force | Out-Null
    Invoke-TestGit $remote @('init', '--quiet')
    Configure-Identity $remote
    Add-TestCommit $remote 'seed.txt' 'seed'
    Invoke-TestGit $remote @('branch', '-M', 'main')
    Invoke-TestGit $remote @('config', 'receive.denyCurrentBranch', 'refuse')
    Invoke-TestGit $base @('clone', '--quiet', $remote, $local)
    Configure-Identity $local
    [PSCustomObject]@{ Base = $base; Remote = $remote; Local = $local }
}

function Assert-ThrowsLike([scriptblock]$action, [string]$pattern, [string]$message) {
    try {
        & $action
    } catch {
        if ($_.Exception.Message -notmatch $pattern) {
            throw "$message Wrong error: $($_.Exception.Message)"
        }
        return
    }
    throw "$message Expected an exception."
}

try {
    $cleanAhead = New-BareTopology 'clean-ahead'
    $clean = Invoke-VerifiedGitRemoteSync -Repository $cleanAhead.Local -Remote origin -Branch main
    if (-not $clean.Verified -or $clean.Pushed) {
        throw 'Clean synchronized branch should verify without pushing.'
    }

    'unstaged' | Set-Content -LiteralPath (Join-Path $cleanAhead.Local 'staged.txt') -Encoding utf8
    if (Test-GitStagedChanges -Repository $cleanAhead.Local) {
        throw 'Unstaged changes must not be treated as staged.'
    }
    Invoke-TestGit $cleanAhead.Local @('add', '--', 'staged.txt')
    if (-not (Test-GitStagedChanges -Repository $cleanAhead.Local)) {
        throw 'Staged changes were not detected.'
    }
    Invoke-TestGit $cleanAhead.Local @('commit', '-m', 'ahead test')
    $ahead = Invoke-VerifiedGitRemoteSync -Repository $cleanAhead.Local -Remote origin -Branch main
    if (-not $ahead.Pushed -or -not $ahead.Verified) {
        throw 'Ahead branch was not pushed and verified.'
    }

    $behind = New-BareTopology 'behind'
    Add-TestCommit $behind.Peer 'remote.txt' 'remote'
    Invoke-TestGit $behind.Peer @('push', '--quiet', 'origin', 'main')
    Assert-ThrowsLike {
        Invoke-VerifiedGitRemoteSync -Repository $behind.Local -Remote origin -Branch main
    } '\bbehind\b' 'Remote-newer branch must be blocked.'

    $diverged = New-BareTopology 'diverged'
    Add-TestCommit $diverged.Local 'local.txt' 'local'
    Add-TestCommit $diverged.Peer 'remote.txt' 'remote'
    Invoke-TestGit $diverged.Peer @('push', '--quiet', 'origin', 'main')
    Assert-ThrowsLike {
        Invoke-VerifiedGitRemoteSync -Repository $diverged.Local -Remote origin -Branch main
    } '\bdiverged\b' 'Diverged branch must be blocked.'

    $pushFailure = New-NonBareTopology 'push-failure'
    Add-TestCommit $pushFailure.Local 'local.txt' 'local'
    Assert-ThrowsLike {
        Invoke-VerifiedGitRemoteSync -Repository $pushFailure.Local -Remote origin -Branch main
    } 'git push .* failed with exit code' 'Push failure must propagate.'

    $mismatch = New-BareTopology 'oid-mismatch'
    Add-TestCommit $mismatch.Local 'local.txt' 'local'
    Assert-ThrowsLike {
        Assert-GitRemoteHeadMatches -Repository $mismatch.Local -Remote origin -Branch main
    } 'remote OID mismatch' 'Fresh remote OID mismatch must fail.'

    $auto = New-BareTopology 'auto-archive'
    $autoTools = Join-Path $auto.Local 'tools'
    New-Item -ItemType Directory -Path $autoTools -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'auto-archive-push.ps1') -Destination $autoTools
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'git-cloud-sync.ps1') -Destination $autoTools
    Invoke-TestGit $auto.Local @('add', '--', 'tools')
    Invoke-TestGit $auto.Local @('commit', '-m', 'install auto archive')
    Invoke-TestGit $auto.Local @('push', '--quiet', 'origin', 'main')

    $profileBefore = $env:USERPROFILE
    try {
        $env:USERPROFILE = Join-Path $auto.Base 'profile'
        New-Item -ItemType Directory -Path $env:USERPROFILE -Force | Out-Null
        $autoScript = Join-Path $autoTools 'auto-archive-push.ps1'

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoScript 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Clean auto-archive run failed.'
        }

        Add-TestCommit $auto.Local 'ahead.txt' 'ahead'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoScript 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Clean worktree with an ahead commit was not repaired by auto-archive.'
        }
        Assert-GitRemoteHeadMatches -Repository $auto.Local -Remote origin -Branch main | Out-Null

        $docs = Join-Path $auto.Local 'docs'
        New-Item -ItemType Directory -Path $docs -Force | Out-Null
        'safe' | Set-Content -LiteralPath (Join-Path $docs 'safe.md') -Encoding utf8
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoScript 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Safe worktree change was not committed and pushed by auto-archive.'
        }
        Assert-GitRemoteHeadMatches -Repository $auto.Local -Remote origin -Branch main | Out-Null

        $preStagedPath = Join-Path $auto.Local 'pre-staged.txt'
        'preserve staged state' | Set-Content -LiteralPath $preStagedPath -Encoding utf8
        Invoke-TestGit $auto.Local @('add', '--', 'pre-staged.txt')
        $headBeforeBlockedRun = (Invoke-GitCapture -Repository $auto.Local -Arguments @('rev-parse', 'HEAD')).Text
        $savedEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoScript 2>&1 | Out-Null
            $stagedExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedEap
        }
        if ($stagedExitCode -eq 0) {
            throw 'Pre-existing staged work should block auto-archive.'
        }
        $stagedNames = (Invoke-GitCapture -Repository $auto.Local -Arguments @(
            'diff', '--cached', '--name-only'
        )).Lines
        if (@($stagedNames).Count -ne 1 -or [string]$stagedNames[0] -ne 'pre-staged.txt') {
            throw "Blocked run did not preserve the pre-run staged tree: $($stagedNames -join ', ')"
        }
        $headAfterBlockedRun = (Invoke-GitCapture -Repository $auto.Local -Arguments @('rev-parse', 'HEAD')).Text
        if ($headAfterBlockedRun -ne $headBeforeBlockedRun) {
            throw 'Blocked run unexpectedly created a commit.'
        }
        Invoke-TestGit $auto.Local @('reset', '--quiet', 'HEAD', '--', 'pre-staged.txt')
        Remove-Item -LiteralPath $preStagedPath -Force

        (('OPENCLAW_GATEWAY_' + 'PASSWORD') + '=definitely-not-a-placeholder') |
            Set-Content -LiteralPath (Join-Path $auto.Local '.env') -Encoding utf8
        $savedEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoScript 2>&1 | Out-Null
            $secretExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedEap
        }
        if ($secretExitCode -eq 0) {
            throw 'Secret-like content should abort auto-archive.'
        }
        $stagedNames = (Invoke-GitCapture -Repository $auto.Local -Arguments @(
            'diff', '--cached', '--name-only'
        )).Lines
        if (@($stagedNames).Count -ne 0) {
            throw "Secret abort did not restore the initially empty staged tree: $($stagedNames -join ', ')"
        }
    } finally {
        $env:USERPROFILE = $profileBefore
    }

    $wrapperDir = Join-Path $testRoot 'memory-wrapper'
    New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'memory_backup_hidden.vbs') -Destination $wrapperDir
    $wrapperMarker = Join-Path $wrapperDir 'marker.txt'
    ("'memory' | Set-Content -LiteralPath '{0}' -Encoding utf8; exit 7" -f $wrapperMarker) |
        Set-Content -LiteralPath (Join-Path $wrapperDir 'backup-memory.ps1') -Encoding utf8
    ("'openclaw' | Add-Content -LiteralPath '{0}' -Encoding utf8; exit 0" -f $wrapperMarker) |
        Set-Content -LiteralPath (Join-Path $wrapperDir 'backup-openclaw.ps1') -Encoding utf8
    $savedEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & cscript.exe //nologo (Join-Path $wrapperDir 'memory_backup_hidden.vbs') 2>&1 | Out-Null
        $wrapperExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedEap
    }
    if ($wrapperExitCode -ne 7) {
        throw "Memory hidden wrapper did not propagate the first failure (exit=$wrapperExitCode)."
    }
    $wrapperRuns = @(Get-Content -LiteralPath $wrapperMarker)
    if ($wrapperRuns.Count -ne 2 -or $wrapperRuns[0] -ne 'memory' -or $wrapperRuns[1] -ne 'openclaw') {
        throw "Memory hidden wrapper did not attempt both backups: $($wrapperRuns -join ', ')"
    }

    Write-Host 'PASS: verified Git cloud sync handles clean, staged, ahead, behind, diverged, push-failure, and OID-mismatch states.'
} finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTest) -like 'openclaw-git-sync-test-*') {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
    }
}
