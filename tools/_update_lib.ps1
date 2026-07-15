# =====================================================================
#  _update_lib.ps1 — Shared helpers for OpenClaw managed-component adapter
#  Pure functions: version parse, relation, channel map
#  Side-effectful helpers: npm invoke, port wait, config read/write
#  Dot-sourced by managed-component.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

# --- Constants (single wait budget owned by owner adapter) ---
$script:OC_PORT = 18789
$script:OC_TASK = 'OpenClaw Gateway'
$script:OC_UPDATE_TASK = 'OpenClaw Update'
$script:OC_WAIT_MAX_SEC = 120
$script:OC_WAIT_STABLE_SEC = 10

# --- Pure: version token extraction ---
function Get-OpenClawVersionToken {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '(\d{4}\.\d{1,2}\.\d{1,2}(?:-[\w.]+)?)') { return $Matches[1] }
    if ($Text -match '(\d+\.\d+\.\d+(?:-[\w.]+)?)') { return $Matches[1] }
    return $null
}

# --- Pure: parse version into comparable parts ---
function Parse-VersionToken {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $v = $Version.Trim()
    if ($v -notmatch '^(\d+(?:\.\d+)*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$') {
        return $null
    }
    $core = $Matches[1]
    $pre = if ($Matches[2]) { $Matches[2] } else { $null }
    $parts = $core -split '\.'
    $nums = @()
    foreach ($p in $parts) {
        [long]$n = 0
        if (-not [long]::TryParse($p, [ref]$n)) { return $null }
        $nums += $n
    }
    while ($nums.Count -lt 3) { $nums += 0 }
    return [pscustomobject]@{ Parts = $nums; PreRelease = $pre; Raw = $v }
}

# --- Pure: compare two version tokens (returns -1/0/1) ---
function Compare-Versions {
    param([string]$Current, [string]$Target)
    $c = Parse-VersionToken -Version $Current
    $t = Parse-VersionToken -Version $Target
    if (-not $c -or -not $t) { return $null }
    $maxLen = [Math]::Max($c.Parts.Count, $t.Parts.Count)
    for ($i = 0; $i -lt $maxLen; $i++) {
        $cv = if ($i -lt $c.Parts.Count) { $c.Parts[$i] } else { 0 }
        $tv = if ($i -lt $t.Parts.Count) { $t.Parts[$i] } else { 0 }
        if ($cv -lt $tv) { return -1 }
        if ($cv -gt $tv) { return 1 }
    }
    if ($c.PreRelease -and -not $t.PreRelease) { return -1 }
    if (-not $c.PreRelease -and $t.PreRelease) { return 1 }
    if ($c.PreRelease -and $t.PreRelease) {
        $cIds = $c.PreRelease -split '\.'
        $tIds = $t.PreRelease -split '\.'
        $limit = [Math]::Min($cIds.Count, $tIds.Count)
        for ($i = 0; $i -lt $limit; $i++) {
            [long]$cn = 0
            [long]$tn = 0
            $cNumeric = [long]::TryParse($cIds[$i], [ref]$cn)
            $tNumeric = [long]::TryParse($tIds[$i], [ref]$tn)
            if ($cNumeric -and $tNumeric) {
                if ($cn -lt $tn) { return -1 }
                if ($cn -gt $tn) { return 1 }
                continue
            }
            if ($cNumeric -and -not $tNumeric) { return -1 }
            if (-not $cNumeric -and $tNumeric) { return 1 }
            $ordinal = [string]::CompareOrdinal($cIds[$i], $tIds[$i])
            if ($ordinal -lt 0) { return -1 }
            if ($ordinal -gt 0) { return 1 }
        }
        if ($cIds.Count -lt $tIds.Count) { return -1 }
        if ($cIds.Count -gt $tIds.Count) { return 1 }
        return 0
    }
    return 0
}

# --- Pure: channel -> npm dist-tag map ---
function ConvertTo-NpmTag {
    param([string]$Channel)
    switch ($Channel) {
        'beta' { return 'beta' }
        'dev'  { return 'dev' }
        default { return 'latest' }
    }
}

# --- Pure: determine relation enum (R7: strict, no "unknown can update") ---
function Get-VersionRelation {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion,
        [bool]$CurrentProbeOk,
        [bool]$TargetProbeOk,
        [string]$Channel,
        [bool]$ChannelResolveOk
    )
    if (-not $CurrentProbeOk -or -not $TargetProbeOk) {
        return 'unknown'
    }
    if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or [string]::IsNullOrWhiteSpace($TargetVersion)) {
        return 'unknown'
    }
    if (-not $ChannelResolveOk) {
        return 'channel_mismatch'
    }
    $cmp = Compare-Versions -Current $CurrentVersion -Target $TargetVersion
    if ($null -eq $cmp) { return 'unknown' }
    switch ($cmp) {
        0  { return 'equal' }
        -1 { return 'behind' }
        1  { return 'ahead' }
        default { return 'unknown' }
    }
}

# --- Side-effectful: invoke external command, stderr-safe ---
function Invoke-ExternalLines {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 60
    )
    $resolved = Get-Command $FilePath -ErrorAction Stop
    $commandPath = [string]$resolved.Source
    $effectiveArgs = [Collections.Generic.List[string]]::new()

    if ([IO.Path]::GetExtension($commandPath) -ieq '.ps1') {
        $cmdSibling = [IO.Path]::ChangeExtension($commandPath, '.cmd')
        if (Test-Path -LiteralPath $cmdSibling) {
            $commandPath = $cmdSibling
        } else {
            $scriptPath = $commandPath
            $commandPath = Join-Path $PSHOME 'pwsh.exe'
            foreach ($prefix in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)) {
                $effectiveArgs.Add($prefix)
            }
        }
    }
    foreach ($argument in $ArgumentList) { $effectiveArgs.Add([string]$argument) }

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $commandPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in $effectiveArgs) { $psi.ArgumentList.Add($argument) }

    $proc = [Diagnostics.Process]::Start($psi)
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $waited = $proc.WaitForExit([Math]::Max(1, $TimeoutSec) * 1000)
    if (-not $waited) {
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
        try { $proc.WaitForExit() } catch {}
        return [pscustomobject]@{
            ExitCode = -1
            Lines    = @()
            Text     = ''
            Stdout   = ''
            Stderr   = "timeout after ${TimeoutSec}s"
            TimedOut = $true
        }
    }

    $proc.WaitForExit()
    $stdout = [string]$stdoutTask.Result
    $stderr = [string]$stderrTask.Result
    $textParts = @()
    if (-not [string]::IsNullOrWhiteSpace($stdout)) { $textParts += $stdout.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { $textParts += $stderr.TrimEnd() }
    $text = $textParts -join "`n"
    $lines = if ($text) { @($text -split "`r?`n") } else { @() }
    return [pscustomobject]@{
        ExitCode = [int]$proc.ExitCode
        Lines    = $lines
        Text     = $text
        Stdout   = $stdout
        Stderr   = $stderr
        TimedOut = $false
    }
}

# --- Side-effectful: resolve npm.cmd path ---
function Resolve-NpmCmd {
    $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
    if (Test-Path $fallback) { return $fallback }
    $cmd2 = Get-Command npm -ErrorAction SilentlyContinue
    if ($cmd2) { return $cmd2.Source }
    throw 'npm not found on PATH'
}

# --- Side-effectful: inspect/test the listener ---
function Get-PortOwningProcessIds {
    param([int]$Port = $script:OC_PORT)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return @($conn | Select-Object -ExpandProperty OwningProcess -Unique)
}

function Test-PortListening {
    param([int]$Port = $script:OC_PORT)
    return @(Get-PortOwningProcessIds -Port $Port).Count -gt 0
}

# --- Side-effectful: wait for gateway healthy (stable listen) ---
function Wait-GatewayHealthy {
    param(
        [int]$Port = $script:OC_PORT,
        [int]$MaxWaitSec = $script:OC_WAIT_MAX_SEC,
        [int]$StableSec = $script:OC_WAIT_STABLE_SEC,
        [int[]]$PreviousOwningProcessIds = @()
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($MaxWaitSec)
    $stable = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds 1
        $currentPids = @(Get-PortOwningProcessIds -Port $Port)
        $listenerTransitioned = $PreviousOwningProcessIds.Count -eq 0 -or
            @($currentPids | Where-Object { $PreviousOwningProcessIds -notcontains $_ }).Count -gt 0
        if ($currentPids.Count -gt 0 -and $listenerTransitioned) {
            $stable++
            if ($stable -ge $StableSec) { return $true }
        } else {
            $stable = 0
        }
    }
    return $false
}

# --- Side-effectful: read openclaw config value ---
function Get-OCConfigValue {
    param([string]$Key)
    try {
        $run = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('config', 'get', $Key) -TimeoutSec 30
        if ($run.ExitCode -eq 0) { return $run.Stdout.Trim() }
        return $null
    } catch { return $null }
}

# --- Side-effectful: set openclaw config value ---
function Set-OCConfigValue {
    param([string]$Key, [string]$Value)
    try {
        $null = Invoke-ExternalLines -FilePath 'openclaw' -ArgumentList @('config', 'set', $Key, $Value) -TimeoutSec 30
    } catch {}
}

# --- Side-effectful: get scheduled task state ---
function Get-TaskState {
    param([string]$TaskName)
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) { return [string]$task.State }
        return $null
    } catch { return $null }
}

function Write-AtomicUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($fullPath)
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $tmp = "$fullPath.tmp-$PID-$([Guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tmp, $Content, $script:utf8NoBom)
        [IO.File]::Move($tmp, $fullPath, $true)
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Helper: emit JSON to stdout and optionally to ResultPath (R6 atomic write) ---
function Write-JsonResult {
    param(
        [Parameter(Mandatory = $true)]$Data,
        [string]$ResultPath
    )
    $json = $Data | ConvertTo-Json -Depth 10
    Write-Output $json
    if ($ResultPath) {
        Write-AtomicUtf8File -Path $ResultPath -Content $json
    }
}

# --- Helper: emit error JSON to stderr and optionally to ResultPath, exit non-zero ---
function Write-JsonError {
    param(
        [Parameter(Mandatory = $true)][string]$ErrorType,
        [Parameter(Mandatory = $true)][string]$ComponentId,
        [string]$Message,
        [string]$ResultPath,
        [int]$ExitCode = 1
    )
    $err = [ordered]@{
        schema        = 'managed_route_error.v1'
        error         = $ErrorType
        component_id  = $ComponentId
        message       = $Message
        observed_utc  = [DateTime]::UtcNow.ToString('o')
    }
    $json = $err | ConvertTo-Json -Depth 5
    if ($ResultPath) {
        Write-AtomicUtf8File -Path $ResultPath -Content $json
    }
    [Console]::Out.WriteLine($json)
    [Console]::Error.WriteLine($json)
    exit $ExitCode
}

# --- Helper: test if current process is admin ---
function Test-IsAdmin {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
