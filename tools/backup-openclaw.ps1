# =====================================================================
#  backup-openclaw.ps1 — 备份 OpenClaw 配置+工作区到私有云（恢复用）
# ---------------------------------------------------------------------
#  config（openclaw.json/auth-profiles.json/config.yml/.env，含密钥）
#  + workspace（人格/记忆/技能/脚本，排除 node_modules）
#  → 本地 E:\Projects\Backups\openclaw-backup → 私有仓库 wlyaaaaa/openclaw-backup。
#  由计划任务每日 20:20 + 22:20 自动跑。**私有仓库，含密钥，切勿公开。**
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\backup-openclaw.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$srcCfg = Join-Path $env:USERPROFILE ".openclaw"
$srcWs  = Join-Path $srcCfg "workspace"
$repo   = "E:\Projects\Backups\openclaw-backup"
$log    = Join-Path (Join-Path $env:USERPROFILE ".openclaw\logs\OpenClawGateway") "backup-openclaw.log"
. (Join-Path $PSScriptRoot 'git-cloud-sync.ps1')

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

Log "=== OpenClaw Backup — start ==="
if (-not (Test-Path (Join-Path $repo '.git'))) { Log "[ERROR] 备份仓库未初始化: $repo"; exit 1 }
if (-not (Test-Path -LiteralPath $srcCfg -PathType Container)) { Log "[ERROR] 配置目录不存在: $srcCfg"; exit 1 }
if (-not (Test-Path -LiteralPath $srcWs -PathType Container)) { Log "[ERROR] 工作区目录不存在: $srcWs"; exit 1 }

try {
    $branch = Get-GitCurrentBranch -Repository $repo
    if ($branch -ne 'main') {
        throw "Unexpected cloud backup branch '$branch'; expected 'main'."
    }
    # 在覆盖专用备份工作树前先确认远端没有更新或分叉。
    Get-GitRemoteState -Repository $repo -Remote 'origin' -Branch $branch | Out-Null

    # 1) config（含密钥）。源文件被删除时同步删除旧备份，避免恢复陈旧配置。
    $configDst = Join-Path $repo 'config'
    New-Item -ItemType Directory -Path $configDst -Force | Out-Null
    foreach ($f in 'openclaw.json','auth-profiles.json','config.yml','.env') {
        $sourceFile = Join-Path $srcCfg $f
        $destinationFile = Join-Path $configDst $f
        if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
            Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force
        } elseif (Test-Path -LiteralPath $destinationFile) {
            Remove-Item -LiteralPath $destinationFile -Force
        }
    }

    # 2) workspace（排除 node_modules / 缓存 / .git）
    robocopy $srcWs (Join-Path $repo 'workspace') /MIR /XD node_modules .git .openclaw-repair .clawhub /XF package-lock.json /NFL /NDL /NJH /NJS /NP 2>$null | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "workspace robocopy failed with exit code $LASTEXITCODE"
    }

    # 3) 仅在暂存区真的有变化时提交；随后无条件验证/补推远端。
    Invoke-GitCapture -Repository $repo -Arguments @('add', '-A') | Out-Null
    if (Test-GitStagedChanges -Repository $repo) {
        Invoke-GitCapture -Repository $repo -Arguments @(
            'commit', '-m', ("openclaw snapshot {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
        ) | Out-Null
    }
    $sync = Invoke-VerifiedGitRemoteSync -Repository $repo -Remote 'origin' -Branch $branch
    $verb = if ($sync.Pushed) { '已推送' } else { '已是最新' }
    Log "[OK] 私有云备份$verb，远端 OID 回读一致 wlyaaaaa/openclaw-backup"
} catch {
    Log "[ERROR] 私有云备份失败（任务返回失败以触发重试）: $_"
    throw
}
Log "=== done ==="
