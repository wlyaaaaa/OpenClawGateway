<#
.SYNOPSIS  定时把 OpenClawGateway 归档自动提交并推送 GitHub（带机密扫描守卫）。
.DESCRIPTION
  由 "OpenClawGateway AutoPush" 计划任务每日调用：有改动才提交；推送前扫描机密，命中即中止。
.NOTES  无改动则静默退出。
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'logs\OpenClawGateway'; New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'auto-push.log'
. (Join-Path $PSScriptRoot 'git-cloud-sync.ps1')
function Log([string]$m){ ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) | Out-File $log -Append -Encoding utf8 }

function Abort-Push([string]$reason, [string]$RestoreIndexTree) {
    if ($RestoreIndexTree) {
        try {
            # Restore the exact staged tree that existed before this automation
            # ran, without touching working-tree content.
            Invoke-GitCapture -Repository $repo -Arguments @('read-tree', $RestoreIndexTree) | Out-Null
        } catch {
            Log "[WARN] failed to restore pre-run staged tree: $_"
        }
    }
    throw $reason
}

function Test-ForbiddenTrackedPath([string]$path) {
    if ($path -like 'journal/*') { return $true }
    if ($path -like 'logs/*') { return $true }
    if ($path -like '.secrets/*') { return $true }
    if ($path -like 'secrets-backup/*') { return $true }
    if ($path -like 'memory-backup/*') { return $true }
    if ($path -like 'codex-memory-backup/*') { return $true }
    if ($path -like 'gemini-memory-backup/*') { return $true }
    if ($path -eq 'CLAUDE.md') { return $true }
    if ($path -eq 'docs/AUDIT.md') { return $true }
    if ($path -eq 'openclaw_task.xml') { return $true }
    if ($path -eq 'auth-profiles.json') { return $true }
    if ($path -eq 'openclaw.json') { return $true }
    if ($path -eq 'README.pdf' -or $path -like 'docs/*.pdf') { return $true }
    if ($path -like '*.patch.json') { return $true }
    if ($path -like '*.env' -or $path -like '.env*') { return $true }
    return $false
}

try {
    # Public repo invariant: these paths must never be tracked, even if someone
    # changes .gitignore or force-adds files manually.
    $trackedFiles = (Invoke-GitCapture -Repository $repo -Arguments @('ls-files')).Lines
    $forbiddenTracked = @($trackedFiles | Where-Object { Test-ForbiddenTrackedPath ([string]$_) })
    if ($forbiddenTracked.Count -gt 0) {
        Abort-Push "public repository contains forbidden tracked paths: $($forbiddenTracked -join ', ')"
    }

    # The scheduler must never absorb a user's pre-existing staged work into an
    # automatic commit. Leave both index and worktree untouched and require a
    # later clean-index run instead.
    if (Test-GitStagedChanges -Repository $repo) {
        Abort-Push 'pre-existing staged changes detected; refusing automatic add/commit/push'
    }

    $branch = Get-GitCurrentBranch -Repository $repo
    # Fetch and block behind/diverged before making an automatic commit.
    Get-GitRemoteState -Repository $repo -Remote 'origin' -Branch $branch | Out-Null

    # Only create a commit when staging produced a real tree change.
    $dirty = (Invoke-GitCapture -Repository $repo -Arguments @('status', '--porcelain')).Text
    $committed = $false
    if ($dirty) {
        $indexTreeBefore = (Invoke-GitCapture -Repository $repo -Arguments @('write-tree')).Text
        Invoke-GitCapture -Repository $repo -Arguments @('add', '-A') | Out-Null

        # 排除本脚本自身（它定义了模式串，避免自我误报）
        $stagedText = (Invoke-GitCapture -Repository $repo -Arguments @(
            'diff', '--cached', '--text', '--', '.', ':(exclude)tools/auto-archive-push.ps1'
        )).Text
        # 模式拆分拼接，使本文件源码不字面包含历史完整值，同时覆盖常见新泄露形态。
        $patterns = @(
            ('8857'+'353244'),
            ('sk-'+'ws-'),
            ('wlySecure'+'Claw2026'),
            ('-----BEGIN '+'PRIVATE KEY-----'),
            ('AAHswW0'+'qeNXs'),
            ('Vvul'+'WjvTbSDx'),
            'sk-[A-Za-z0-9_-]{20,}',
            'Authorization:\s*Bearer\s+\S+',
            '"botToken"\s*:\s*"(?!<)',
            'api_key:\s*["'']?(?!<|PLACEHOLDER|placeholder)[A-Za-z0-9._-]{16,}',
            'OPENCLAW_GATEWAY_PASSWORD\s*[:=]\s*["'']?(?!<)'
        ) -join '|'
        if ($stagedText -match $patterns) {
            Abort-Push '检测到疑似机密，已中止自动推送（请人工检查）' -RestoreIndexTree $indexTreeBefore
        }

        if (Test-GitStagedChanges -Repository $repo) {
            $msg = 'chore: auto-archive ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
            Invoke-GitCapture -Repository $repo -Arguments @(
                '-c', 'user.name=吴乐阳',
                '-c', 'user.email=wlyaaaaa@gmail.com',
                'commit', '--quiet', '-m', $msg
            ) | Out-Null
            $committed = $true
        }
    }

    # This runs even when the worktree is clean, so a prior local commit cannot
    # remain silently unpushed.
    $sync = Invoke-VerifiedGitRemoteSync -Repository $repo -Remote 'origin' -Branch $branch
    $shortHead = (Invoke-GitCapture -Repository $repo -Arguments @('rev-parse', '--short', 'HEAD')).Text
    if ($sync.Pushed) {
        Log "[OK] pushed and remote OID verified: $shortHead"
    } elseif ($committed) {
        Log "[OK] committed and remote OID verified: $shortHead"
    } else {
        Log "[OK] no changes; remote OID verified: $shortHead"
    }
    exit 0
} catch {
    Log "[ABORT] $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
