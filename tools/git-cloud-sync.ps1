$ErrorActionPreference = 'Stop'

function Invoke-GitCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [int[]]$AllowedExitCodes = @(0)
    )

    $savedPreference = $ErrorActionPreference
    $hasNativePreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hasNativePreference) {
        $savedNativePreference = $PSNativeCommandUseErrorActionPreference
    }
    $hadGitPrompt = Test-Path Env:GIT_TERMINAL_PROMPT
    $savedGitPrompt = $env:GIT_TERMINAL_PROMPT
    $hadGcmInteractive = Test-Path Env:GCM_INTERACTIVE
    $savedGcmInteractive = $env:GCM_INTERACTIVE

    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }
        # Hidden scheduled tasks must fail instead of waiting for an invisible
        # credential prompt.
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'Never'
        $output = @(& git -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $savedNativePreference
        }
        if ($hadGitPrompt) {
            $env:GIT_TERMINAL_PROMPT = $savedGitPrompt
        } else {
            Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
        if ($hadGcmInteractive) {
            $env:GCM_INTERACTIVE = $savedGcmInteractive
        } else {
            Remove-Item Env:GCM_INTERACTIVE -ErrorAction SilentlyContinue
        }
        $ErrorActionPreference = $savedPreference
    }

    $text = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if ($AllowedExitCodes -notcontains $exitCode) {
        $displayArgs = $Arguments -join ' '
        if ($text) {
            throw "git $displayArgs failed with exit code $exitCode`: $text"
        }
        throw "git $displayArgs failed with exit code $exitCode"
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Lines    = $output
        Text     = $text
    }
}

function Get-GitCurrentBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $branch = (Invoke-GitCapture -Repository $Repository -Arguments @('branch', '--show-current')).Text
    if (-not $branch) {
        throw 'Detached HEAD or unborn branch cannot be synchronized automatically.'
    }
    return $branch
}

function Test-GitStagedChanges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [string[]]$Pathspec = @()
    )

    $arguments = @('diff', '--cached', '--quiet', '--exit-code')
    if ($Pathspec.Count -gt 0) {
        $arguments += '--'
        $arguments += $Pathspec
    }
    $result = Invoke-GitCapture -Repository $Repository -Arguments $arguments -AllowedExitCodes @(0, 1)
    return ($result.ExitCode -eq 1)
}

function Get-GitRemoteState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [string]$Remote = 'origin',

        [string]$Branch
    )

    if (-not $Branch) {
        $Branch = Get-GitCurrentBranch -Repository $Repository
    }

    $trackingRef = "refs/remotes/$Remote/$Branch"
    $remoteRef = "refs/heads/$Branch"
    $fetchRefspec = "+$remoteRef`:$trackingRef"
    Invoke-GitCapture -Repository $Repository -Arguments @(
        'fetch', '--quiet', '--prune', $Remote, $fetchRefspec
    ) | Out-Null

    $localOid = (Invoke-GitCapture -Repository $Repository -Arguments @('rev-parse', 'HEAD')).Text
    $trackingOid = (Invoke-GitCapture -Repository $Repository -Arguments @('rev-parse', $trackingRef)).Text
    $countsText = (Invoke-GitCapture -Repository $Repository -Arguments @(
        'rev-list', '--left-right', '--count', "HEAD...$trackingRef"
    )).Text
    $counts = @($countsText -split '\s+')
    if ($counts.Count -ne 2) {
        throw "Unexpected git divergence output: $countsText"
    }

    $ahead = [int]$counts[0]
    $behind = [int]$counts[1]
    if ($behind -gt 0) {
        $kind = if ($ahead -gt 0) { 'diverged' } else { 'behind' }
        throw "Local branch $Branch is $kind relative to $Remote/$Branch (ahead=$ahead, behind=$behind); refusing automatic backup commit/push."
    }

    [PSCustomObject]@{
        Repository  = $Repository
        Remote      = $Remote
        Branch      = $Branch
        RemoteRef   = $remoteRef
        TrackingRef = $trackingRef
        LocalOid    = $localOid
        TrackingOid = $trackingOid
        Ahead       = $ahead
        Behind      = $behind
    }
}

function Assert-GitRemoteHeadMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [string]$Remote = 'origin',

        [Parameter(Mandatory = $true)]
        [string]$Branch
    )

    $localOid = (Invoke-GitCapture -Repository $Repository -Arguments @('rev-parse', 'HEAD')).Text
    $remoteRef = "refs/heads/$Branch"
    $remoteText = (Invoke-GitCapture -Repository $Repository -Arguments @(
        'ls-remote', '--exit-code', $Remote, $remoteRef
    )).Text
    $remoteLine = @($remoteText -split "\r?\n" | Where-Object { $_ -match "\s$([regex]::Escape($remoteRef))$" }) |
        Select-Object -First 1
    if (-not $remoteLine) {
        throw "Fresh remote readback did not return $Remote/$Branch."
    }
    $remoteOid = @($remoteLine -split '\s+')[0]
    if (-not [string]::Equals($localOid, $remoteOid, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Fresh remote OID mismatch for $Remote/$Branch (local=$localOid, remote=$remoteOid)."
    }
    return $remoteOid
}

function Invoke-VerifiedGitRemoteSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [string]$Remote = 'origin',

        [string]$Branch
    )

    $state = Get-GitRemoteState -Repository $Repository -Remote $Remote -Branch $Branch
    $pushed = $false
    if ($state.Ahead -gt 0) {
        Invoke-GitCapture -Repository $Repository -Arguments @(
            'push', '--quiet', $state.Remote, "HEAD:$($state.RemoteRef)"
        ) | Out-Null
        $pushed = $true
    }

    $remoteOid = Assert-GitRemoteHeadMatches -Repository $Repository -Remote $state.Remote -Branch $state.Branch
    [PSCustomObject]@{
        Branch    = $state.Branch
        Ahead     = $state.Ahead
        Behind    = $state.Behind
        Pushed    = $pushed
        Verified  = $true
        RemoteOid = $remoteOid
    }
}
