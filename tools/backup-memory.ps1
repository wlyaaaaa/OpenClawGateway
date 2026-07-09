# =====================================================================
#  backup-memory.ps1 — 备份 Claude Code 记忆（.claude projects memory）
# ---------------------------------------------------------------------
#  记忆含本项目运维上下文（路径/模型/安全态等，非原始密钥），
#  备份到本地时间戳目录并保留最近 N 份；**不入公开仓库**（memory-backup/ 已 gitignore）。
#  由计划任务「OpenClaw Memory Backup」在晚间 20:20 + 22:20 各跑一次。
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\backup-memory.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$src       = "C:\Users\10979\.claude\projects"
$root      = "E:\Projects\Tools\OpenClawGateway\memory-backup"
$cloudRepo = "E:\Projects\Backups\claude-memory"   # 私有云备份仓库 wlyaaaaa/claude-memory
$keep      = 30
$log       = "E:\Projects\Tools\OpenClawGateway\logs\backup-memory.log"

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

# 云备份：镜像记忆 .md 到私有仓库并推送（非致命；本地快照已成功）
# 注意：git 的 LF/CRLF 警告走 stderr，必须用 2>$null + 放宽 EAP，否则会被 Stop 当错误中断。
if (Test-Path (Join-Path $cloudRepo '.git')) {
    $eapSave = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # 迁移到 project/memory/*.md 结构，避免多个 MEMORY.md 互相覆盖；README 保留在根目录。
        Get-ChildItem -LiteralPath $cloudRepo -File -Filter '*.md' |
            Where-Object { $_.Name -ne 'README.md' } |
            Remove-Item -Force

        foreach ($entry in $memoryDirs) {
            $projectCloudDir = Join-Path $cloudRepo (Join-Path $entry.ProjectName 'memory')
            New-Item -ItemType Directory -Path $projectCloudDir -Force | Out-Null
            robocopy $entry.MemoryPath $projectCloudDir *.md /MIR /NJH /NJS /NFL /NDL 2>$null | Out-Null
        }
        $changed = (& git -C $cloudRepo status --porcelain 2>$null) -join ''
        if ($changed) {
            & git -C $cloudRepo add -A 2>$null | Out-Null
            & git -C $cloudRepo commit -m ("memory snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>$null | Out-Null
            & git -C $cloudRepo push origin main 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Log "[OK] 云备份已推送 (private: wlyaaaaa/claude-memory)" }
            else { Log "[WARN] 云备份 push 退出码 $LASTEXITCODE（本地快照已成功）" }
        } else {
            Log "[..] 云备份无变化，跳过推送"
        }
    } catch {
        Log "[WARN] 云备份失败（本地快照已成功）: $_"
    } finally {
        $ErrorActionPreference = $eapSave
    }
} else {
    Log "[..] 云备份仓库未初始化（$cloudRepo），跳过"
}

Log "=== done (本地 $($dirs.Count) 份) ==="
