# =====================================================================
#  backup-openclaw.ps1 — 备份 OpenClaw 配置+工作区到私有云（恢复用）
# ---------------------------------------------------------------------
#  config（openclaw.json/auth-profiles.json/config.yml/.env，含密钥）
#  + workspace（人格/记忆/技能/脚本，排除 node_modules）
#  → 本地 E:\OpenClawBackup → 私有仓库 wlyaaaaa/openclaw-backup。
#  由计划任务每日 20:20 + 22:20 自动跑。**私有仓库，含密钥，切勿公开。**
#  用法：powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\tools\backup-openclaw.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$srcCfg = "C:\Users\10979\.openclaw"
$srcWs  = "C:\Users\10979\.openclaw\workspace"
$repo   = "E:\OpenClawBackup"
$log    = "E:\OpenClawGateway\logs\backup-openclaw.log"

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

Log "=== OpenClaw Backup — start ==="
if (-not (Test-Path (Join-Path $repo '.git'))) { Log "[ERROR] 备份仓库未初始化: $repo"; exit 1 }

# 1) config（含密钥）
New-Item -ItemType Directory -Path (Join-Path $repo 'config') -Force | Out-Null
foreach ($f in 'openclaw.json','auth-profiles.json','config.yml','.env') {
    $p = Join-Path $srcCfg $f
    if (Test-Path $p) { Copy-Item $p (Join-Path $repo 'config') -Force }
}

# 2) workspace（排除 node_modules / 缓存 / .git）
robocopy $srcWs (Join-Path $repo 'workspace') /MIR /XD node_modules .git .openclaw-repair .clawhub /XF package-lock.json /NFL /NDL /NJH /NJS /NP 2>$null | Out-Null

# 3) 提交并推送私有云（git 警告走 stderr，需放宽 EAP + 2>$null）
$eapSave = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $changed = (& git -C $repo status --porcelain 2>$null) -join ''
    if ($changed) {
        & git -C $repo add -A 2>$null | Out-Null
        & git -C $repo commit -m ("openclaw snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>$null | Out-Null
        & git -C $repo push origin main 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "[OK] 已推送私有云 wlyaaaaa/openclaw-backup" }
        else { Log "[WARN] push 退出码 $LASTEXITCODE（本地已更新）" }
    } else {
        Log "[..] 无变化，跳过推送"
    }
} catch {
    Log "[WARN] 云推送失败（本地已更新）: $_"
} finally {
    $ErrorActionPreference = $eapSave
}
Log "=== done ==="
