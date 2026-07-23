# =====================================================================
#  backup-memory.ps1 — 备份 Claude Code 记忆（.claude projects memory）
# ---------------------------------------------------------------------
#  记忆含本项目运维上下文（路径/模型/安全态等，非原始密钥），
#  备份到私有本地时间戳目录并保留最近 N 份；不写入公开仓库工作树。
#  由计划任务「OpenClaw Memory Backup」在晚间 20:20 + 22:20 各跑一次。
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\backup-memory.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$src       = Join-Path $env:USERPROFILE ".claude\projects"
$root      = Join-Path $env:USERPROFILE ".openclaw\memory-backup\claude"
$cloudRepo = "E:\Projects\Backups\claude-memory"   # 私有云备份仓库 wlyaaaaa/claude-memory
$keep      = 30
$log       = Join-Path (Join-Path $env:USERPROFILE ".openclaw\logs\OpenClawGateway") "backup-memory.log"
. (Join-Path $PSScriptRoot 'git-cloud-sync.ps1')

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

Log "=== Memory Backup — start ==="
if (-not (Test-Path $src)) { Log "[ERROR] Claude projects 目录不存在: $src"; exit 1 }

$memoryDirs = Get-ChildItem -LiteralPath $src -Directory |
    ForEach-Object {
        $memoryPath = Join-Path $_.FullName 'memory'
        if (Test-Path $memoryPath) {
            [PSCustomObject]@{
                ProjectName = $_.Name
                MemoryPath  = $memoryPath
            }
        }
    }
if (-not $memoryDirs) { Log "[ERROR] 未找到任何 Claude project memory 目录: $src"; exit 1 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $root $stamp
New-Item -ItemType Directory -Path $dst -Force | Out-Null
foreach ($entry in $memoryDirs) {
    $projectDst = Join-Path $dst (Join-Path $entry.ProjectName 'memory')
    New-Item -ItemType Directory -Path $projectDst -Force | Out-Null
    Copy-Item -Path (Join-Path $entry.MemoryPath '*') -Destination $projectDst -Recurse -Force
}
$n = (Get-ChildItem $dst -Recurse -File -Filter '*.md').Count
Log "[OK] 已备份 $($memoryDirs.Count) 个项目 / $n 个记忆文件 -> $dst"

# 轮换：仅保留最近 $keep 份
$dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
if ($dirs.Count -gt $keep) {
    $dirs | Select-Object -Skip $keep | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Log "[..] 清理旧备份 $($_.Name)"
    }
}

# 云备份：镜像记忆 .md 到私有仓库并推送。云端失败会让计划任务返回非零，
# 便于任务调度器执行重试；已经完成的本地时间戳快照仍然保留。
if (Test-Path (Join-Path $cloudRepo '.git')) {
    try {
        $branch = Get-GitCurrentBranch -Repository $cloudRepo
        if ($branch -ne 'main') {
            throw "Unexpected cloud backup branch '$branch'; expected 'main'."
        }
        # Do not create a local commit on top of remote-newer/diverged history.
        Get-GitRemoteState -Repository $cloudRepo -Remote 'origin' -Branch $branch | Out-Null

        # 迁移到 project/memory/*.md 结构，避免多个 MEMORY.md 互相覆盖；README 保留在根目录。
        Get-ChildItem -LiteralPath $cloudRepo -File -Filter '*.md' |
            Where-Object { $_.Name -ne 'README.md' } |
            Remove-Item -Force

        foreach ($entry in $memoryDirs) {
            $projectCloudDir = Join-Path $cloudRepo (Join-Path $entry.ProjectName 'memory')
            New-Item -ItemType Directory -Path $projectCloudDir -Force | Out-Null
            robocopy $entry.MemoryPath $projectCloudDir *.md /MIR /NJH /NJS /NFL /NDL 2>$null | Out-Null
            if ($LASTEXITCODE -ge 8) {
                throw "robocopy failed for $($entry.ProjectName) with exit code $LASTEXITCODE"
            }
        }

        Invoke-GitCapture -Repository $cloudRepo -Arguments @('add', '-A') | Out-Null
        if (Test-GitStagedChanges -Repository $cloudRepo) {
            Invoke-GitCapture -Repository $cloudRepo -Arguments @(
                'commit', '-m', ("memory snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
            ) | Out-Null
        }

        # 即使本轮内容无变化，也检查并补推历史上遗留的 ahead commit。
        $sync = Invoke-VerifiedGitRemoteSync -Repository $cloudRepo -Remote 'origin' -Branch $branch
        $verb = if ($sync.Pushed) { '已推送' } else { '已是最新' }
        Log "[OK] 云备份$verb，远端 OID 回读一致 (private: wlyaaaaa/claude-memory)"
    } catch {
        Log "[ERROR] 云备份失败（本地快照已成功，任务返回失败以触发重试）: $_"
        throw
    }
} else {
    Log "[ERROR] 云备份仓库未初始化（$cloudRepo）"
    throw "Cloud backup repo not initialized: $cloudRepo"
}

Log "=== done (本地 $($dirs.Count) 份) ==="
