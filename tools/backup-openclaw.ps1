# =====================================================================
#  backup-openclaw.ps1 — 备份 OpenClaw 配置+工作区到私有云（恢复用）
# ---------------------------------------------------------------------
#  config（openclaw.json/auth-profiles.json/config.yml/.env，含密钥）
#  + workspace（人格/记忆/技能/脚本，排除 node_modules）
#  → 配置中的本地快照与私有仓库。
#  由计划任务每日 20:20 + 22:20 自动跑。**私有仓库，含密钥，切勿公开。**
#  用法：powershell -ExecutionPolicy Bypass -File .\tools\backup-openclaw.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'private-backup-settings.ps1')
$settings = Get-PrivateBackupSettings -DefaultSettingsPath (Join-Path $PSScriptRoot 'private-backup.local.json') -Group 'openclaw'

$srcCfg = $settings.config_root
$srcWs  = $settings.workspace_root
$root   = $settings.snapshot_root
$hotRoot = $settings.hot_snapshot_root
$repo   = $settings.cloud_repo
$keep   = 30
$log    = $settings.log_file
. (Join-Path $PSScriptRoot 'git-cloud-sync.ps1')
. (Join-Path $PSScriptRoot 'g-hot-snapshot.ps1')

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $dir = Split-Path $log
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

Log "=== OpenClaw Backup — start ==="
if (-not (Test-Path (Join-Path $repo '.git'))) { Log '[ERROR] 备份仓库未初始化'; exit 1 }
if (-not (Test-Path -LiteralPath $srcCfg -PathType Container)) { Log '[ERROR] 配置目录不存在'; exit 1 }
if (-not (Test-Path -LiteralPath $srcWs -PathType Container)) { Log '[ERROR] 工作区目录不存在'; exit 1 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $root $stamp
$configSnapshot = Join-Path $dst 'config'
$workspaceSnapshot = Join-Path $dst 'workspace'
$null = New-Item -ItemType Directory -Path $configSnapshot -Force
foreach ($f in 'openclaw.json','auth-profiles.json','config.yml','.env') {
    $sourceFile = Join-Path $srcCfg $f
    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $configSnapshot $f) -Force
    }
}
& robocopy $srcWs $workspaceSnapshot /MIR /XD node_modules .git .openclaw-repair .clawhub /XF package-lock.json /NFL /NDL /NJH /NJS /NP 2>$null | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "local workspace snapshot failed with robocopy exit code $LASTEXITCODE"
}
$localFiles = @(Get-ChildItem -LiteralPath $dst -Recurse -File -Force)
if ($localFiles.Count -eq 0) {
    throw 'OpenClaw local snapshot selected no files.'
}
Log "[OK] 本地快照 $($localFiles.Count) 个文件 / $(($localFiles | Measure-Object Length -Sum).Sum) bytes -> $dst"

$dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
if ($dirs.Count -gt $keep) {
    foreach ($old in @($dirs | Select-Object -Skip $keep)) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force
        Log "[..] 清理旧本地快照 $($old.Name)"
    }
}

$hotResult = Publish-GHotSnapshot -SnapshotPath $dst -HotRoot $hotRoot -SnapshotName $stamp -Keep $keep
Log "[OK] G 热备 $($hotResult.file_count) 个文件 / $($hotResult.total_size_bytes) bytes -> $($hotResult.destination)（SHA-256 回读通过）"

try {
    $branch = Get-GitCurrentBranch -Repository $repo
    if ($branch -ne 'main') {
        throw "Unexpected cloud backup branch '$branch'; expected 'main'."
    }
    # 在覆盖专用备份工作树前先确认远端没有更新或分叉。
    Get-GitRemoteState -Repository $repo -Remote 'origin' -Branch $branch | Out-Null

    # 1) config（含密钥）。以已经完成本地/G回读的同一快照更新私有云。
    $configDst = Join-Path $repo 'config'
    New-Item -ItemType Directory -Path $configDst -Force | Out-Null
    foreach ($f in 'openclaw.json','auth-profiles.json','config.yml','.env') {
        $sourceFile = Join-Path $configSnapshot $f
        $destinationFile = Join-Path $configDst $f
        if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
            Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force
        } elseif (Test-Path -LiteralPath $destinationFile) {
            Remove-Item -LiteralPath $destinationFile -Force
        }
    }

    # 2) workspace 已在本地/G快照阶段完成排除和回读；这里精确镜像同一快照。
    robocopy $workspaceSnapshot (Join-Path $repo 'workspace') /MIR /NFL /NDL /NJH /NJS /NP 2>$null | Out-Null
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
    Log "[OK] 私有云备份$verb，远端 OID 回读一致（private backup repository）"
} catch {
    Log "[ERROR] 私有云备份失败（任务返回失败以触发重试）: $_"
    throw
}
Log "=== done ==="
