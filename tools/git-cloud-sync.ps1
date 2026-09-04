$ErrorActionPreference = 'Stop'

function ConvertTo-GitProxyUri {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ProxyServer
    )

    if ([string]::IsNullOrWhiteSpace($ProxyServer)) {
        return $null
    }

    $proxyValue = $ProxyServer.Trim()
    $selectedKind = 'http'
    if ($proxyValue.Contains(';') -or $proxyValue -match '^[a-zA-Z0-9]+=.+' ) {
        $proxyMap = @{}
        foreach ($entry in @($proxyValue -split ';')) {
            if ($entry -match '^\s*([^=]+)=(.+?)\s*$') {
                $proxyMap[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
            }
        }
        if ($proxyMap.ContainsKey('https')) {
            $selectedKind = 'https'
            $proxyValue = $proxyMap['https']
        } elseif ($proxyMap.ContainsKey('http')) {
            $selectedKind = 'http'
            $proxyValue = $proxyMap['http']
        } elseif ($proxyMap.ContainsKey('socks')) {
            $selectedKind = 'socks'
            $proxyValue = $proxyMap['socks']
        } else {
            return $null
        }
    }

    if ($proxyValue -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        return $proxyValue
    }
    if ($selectedKind -eq 'socks') {
        return "socks5://$proxyValue"
    }
    return "http://$proxyValue"
}

function Get-CurrentSystemGitProxyUri {
    [CmdletBinding()]
    param()

    try {
        $settings = Get-ItemProperty -LiteralPath (
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        ) -ErrorAction Stop
        if ([int]$settings.ProxyEnable -ne 1) {
            return $null
        }
        return ConvertTo-GitProxyUri -ProxyServer ([string]$settings.ProxyServer)
    } catch {
        return $null
    }
}

function Test-GitNetworkFailureText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    return ($Text -match (
        'unable to access|failed to connect|could not connect|could not resolve host|' +
        'connection (?:timed out|was reset|refused)|network is unreachable'
    ))
}

function Invoke-GitCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [int[]]$AllowedExitCodes = @(0),

        # Task Scheduler does not restart a task merely because a completed
        # wscript action returned a non-zero process code.  Keep transient
        # remote transport recovery inside the Git operation instead.  The
        # bounded backoff is long enough to bridge a short proxy/TLS flap but
        # does not retry authentication, policy, or repository-state errors.
        [int[]]$NetworkRetryDelaysSeconds = @(30, 120, 300, 900)
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
    $usedSystemProxy = $false
    $networkRetryCount = 0

    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }
        # Hidden scheduled tasks must fail instead of waiting for an invisible
        # credential prompt.
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'Never'
        while ($true) {
            $output = @(& git -C $Repository @Arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $directText = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
            if ($AllowedExitCodes -notcontains $exitCode -and (Test-GitNetworkFailureText -Text $directText)) {
                # Git for Windows does not automatically consume the current
                # WinINet proxy. Try the live user setting without persisting a
                # local proxy port in Git config.
                $systemProxy = Get-CurrentSystemGitProxyUri
                if ($systemProxy) {
                    $output = @(& git -c "http.proxy=$systemProxy" -C $Repository @Arguments 2>&1)
                    $exitCode = $LASTEXITCODE
                    $usedSystemProxy = $true
                }
            }

            $attemptText = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
            $isTransientNetworkFailure = (
                $AllowedExitCodes -notcontains $exitCode -and
                (Test-GitNetworkFailureText -Text $attemptText)
            )
            if (-not $isTransientNetworkFailure -or $networkRetryCount -ge $NetworkRetryDelaysSeconds.Count) {
                break
            }

            $delaySeconds = [Math]::Max(0, [int]$NetworkRetryDelaysSeconds[$networkRetryCount])
            $networkRetryCount++
            if ($delaySeconds -gt 0) {
                Start-Sleep -Seconds $delaySeconds
            }
        }
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
        UsedSystemProxy = $usedSystemProxy
        NetworkRetryCount = $networkRetryCount
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
