# =====================================================================
#  backup-memory.ps1 — 备份 Claude Code 记忆（.claude memory）
# ---------------------------------------------------------------------
#  记忆含本项目运维上下文（路径/模型/安全态等，非原始密钥），
#  备份到本地时间戳目录并保留最近 N 份；**不入公开仓库**（memory-backup/ 已 gitignore）。
#  由计划任务「OpenClaw Memory Backup」在凌晨 4 点 + 白天 13 点各跑一次。
#  用法：powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\tools\backup-memory.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$src  = "C:\Users\10979\.claude\projects\E--RamdiskGuardian\memory"
$root = "E:\OpenClawGateway\memory-backup"
$keep = 30
$log  = "E:\OpenClawGateway\logs\backup-memory.log"

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

Log "=== Memory Backup — start ==="
if (-not (Test-Path $src)) { Log "[ERROR] 记忆目录不存在: $src"; exit 1 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $root $stamp
New-Item -ItemType Directory -Path $dst -Force | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
$n = (Get-ChildItem $dst -Recurse -File).Count
Log "[OK] 已备份 $n 个记忆文件 -> $dst"

# 轮换：仅保留最近 $keep 份
$dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
if ($dirs.Count -gt $keep) {
    $dirs | Select-Object -Skip $keep | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Log "[..] 清理旧备份 $($_.Name)"
    }
}
Log "=== done (共 $($dirs.Count) 份) ==="
