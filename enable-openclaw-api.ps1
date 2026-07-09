<#
.SYNOPSIS
  恢复 OpenClaw API 使用 —— 从安全模式退出。
.DESCRIPTION
    1. 从最近一次备份还原 DashScope API key
    2. 保持 Telegram / Feishu 入站渠道开关不变，避免 API key 开关破坏 IM 可用性
    3. 更新通道设为 stable（自动更新仍保持手动，更稳）
    4. 重新开启 Tailscale funnel 公网入口
    5. 重启网关并做健康检查
  说明：IM channel 是否启用由 openclaw.json 长期配置决定，不由 API key 脚本改写。
.NOTES
  以管理员 PowerShell 运行。
#>
$ErrorActionPreference = 'Stop'
$oc   = Join-Path $env:USERPROFILE '.openclaw'
$root = $PSScriptRoot; if (-not $root) { $root = 'E:\Projects\Tools\OpenClawGateway' }
$logDir = Join-Path $oc 'logs\OpenClawGateway'; if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }
$log = Join-Path $logDir 'api-toggle.log'
function Log([string]$m){ $l = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m; $l | Out-File $log -Append -Encoding utf8; Write-Host $l }

$task     = 'OpenClaw Gateway'
$authFile = Join-Path $oc 'auth-profiles.json'
$cfgFile  = Join-Path $oc 'openclaw.json'
$ts       = 'C:\Program Files\Tailscale\tailscale.exe'
$stateFile = Join-Path $logDir 'api-state.json'
$secretBackupRoot = $env:OPENCLAW_SECRET_BACKUP_DIR
if (-not $secretBackupRoot) { $secretBackupRoot = Join-Path $oc 'secrets-backup' }

function Get-TelegramOwnerIds {
    $raw = $env:OC_TELEGRAM_USER_ID
    if (-not $raw -and (Test-Path $cfgFile)) {
        try {
            $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
            $raw = @($cfg.channels.telegram.allowFrom |
                Where-Object { "$_" -match '^\d+$' } |
                Select-Object -First 1) -join ','
        } catch {}
    }
    if (-not $raw) {
        throw 'Set OC_TELEGRAM_USER_ID or keep a numeric channels.telegram.allowFrom value in openclaw.json before changing API mode.'
    }

    $ids = @($raw -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { [int64]$_ })
    if ($ids.Count -eq 0) { throw 'OC_TELEGRAM_USER_ID did not contain a numeric Telegram user ID.' }
    return $ids
}

Log '=== ENABLE: 退出安全模式，恢复 API ==='

# 0. 找到备份目录
$backupDir = $null
if (Test-Path $stateFile) { $backupDir = (Get-Content $stateFile -Raw | ConvertFrom-Json).backup }
if (-not $backupDir -or -not (Test-Path $backupDir)) {
    $latest = Get-ChildItem $secretBackupRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $backupDir = $latest.FullName }
}
if (-not $backupDir) { Log '[ERROR] 找不到备份目录，无法自动还原 key。请手动填回 auth-profiles.json'; throw 'no backup' }
Log "使用备份：$backupDir"

# 1. 停网关
try { Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue } catch {}
$pid18789 = (Get-NetTCPConnection -LocalPort 18789 -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
if ($pid18789) { Stop-Process -Id $pid18789 -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# 2. 还原 API key
$bakAuth = Join-Path $backupDir 'auth-profiles.json'
if (Test-Path $bakAuth) { Copy-Item $bakAuth $authFile -Force; Log '已从备份还原 API key' }
else { Log '[WARN] 备份中无 auth-profiles.json；请手动填回 key' }

# 3. 收敛 Telegram 白名单 / 通道 stable / 开 funnel；不改 Telegram 或 Feishu enabled
$telegramOwnerIds = Get-TelegramOwnerIds
$patch = @{
    update = @{ auto = @{ enabled = $false }; channel = 'stable'; checkOnStart = $true }
    channels = @{ telegram = @{ allowFrom = $telegramOwnerIds; groupAllowFrom = $telegramOwnerIds } }
    gateway = @{ tailscale = @{ mode = 'funnel' } }
} | ConvertTo-Json -Depth 10
$patchFile = Join-Path $logDir 'enable.patch.json'
$patch | Set-Content $patchFile -Encoding utf8
& openclaw config patch --file $patchFile | ForEach-Object { Log "config: $_" }
Log '已恢复 API key + stable 通道 + funnel（IM channel enabled 保持不变）'

# 4. 重启网关 + 健康检查
Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10
$conn = Test-NetConnection 127.0.0.1 -Port 18789 -WarningAction SilentlyContinue
if ($conn.TcpTestSucceeded) { Log '[OK] 网关已恢复并监听 18789' } else { Log '[WARN] 18789 暂未监听，查看 gateway.log' }
if (Test-Path $ts) { & $ts funnel status 2>$null | ForEach-Object { Log "funnel: $_" } }

@{ state = 'enabled'; at = (Get-Date -Format o); backup = $backupDir } | ConvertTo-Json |
    Set-Content $stateFile -Encoding utf8
Log '=== ENABLE 完成。机器人响应取决于长期 IM channel enabled 配置。 ==='
