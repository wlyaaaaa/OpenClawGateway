<#
.SYNOPSIS
  OpenClaw 安全模式 —— 临时禁用 LLM API，杜绝无人值守烧钱。
.DESCRIPTION
  网关照常开机自启 / 监听 18789，但：
    1. 备份并清空 DashScope API key  → 任何模型调用立即失败（零花费）
    2. 关闭全部入站渠道(telegram/feishu/googlechat) → 无外部触发
    3. 关闭 memory-core.dreaming  → 无后台自动思考
    4. 关闭自动更新 / 启动检查      → 无联网超时拖累启动
    5. Telegram allowFrom 收敛为仅本人 ID（移除 "*"）
    6. Tailscale funnel/serve 复位  → 关闭公网暴露
  备份保存在 .\secrets-backup\<时间戳>\，可用 enable-openclaw-api.ps1 一键恢复。
.NOTES
  以管理员 PowerShell 运行。
#>
$ErrorActionPreference = 'Stop'
$oc   = 'C:\Users\10979\.openclaw'
$root = $PSScriptRoot; if (-not $root) { $root = 'E:\Projects\Tools\OpenClawGateway' }
$logDir = Join-Path $root 'logs'; if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force $logDir | Out-Null }
$log = Join-Path $logDir 'api-toggle.log'
function Log([string]$m){ $l = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m; $l | Out-File $log -Append -Encoding utf8; Write-Host $l }

$task     = 'OpenClaw Gateway'
$authFile = Join-Path $oc 'auth-profiles.json'
$cfgFile  = Join-Path $oc 'openclaw.json'
$ts       = 'C:\Program Files\Tailscale\tailscale.exe'
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path (Join-Path $root 'secrets-backup') $stamp
New-Item -ItemType Directory -Force $backupDir | Out-Null

Log '=== DISABLE: 进入安全模式 (零 LLM 花费) ==='

# 1. 停掉网关，防止它在改配置时回写 / 发起调用
try { Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue } catch {}
$pid18789 = (Get-NetTCPConnection -LocalPort 18789 -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
if ($pid18789) { Stop-Process -Id $pid18789 -Force -ErrorAction SilentlyContinue; Log "stopped gateway pid=$pid18789" }
Start-Sleep -Seconds 2

# 2. 备份 配置 + 密钥
Copy-Item $cfgFile  $backupDir -Force -ErrorAction SilentlyContinue
Copy-Item $authFile $backupDir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $oc 'config.yml') $backupDir -Force -ErrorAction SilentlyContinue
Log "已备份 配置/密钥 → $backupDir"

# 3. 清空 DashScope API key（OpenClaw 实际读取的密钥库）
if (Test-Path $authFile) {
    $auth = Get-Content $authFile -Raw | ConvertFrom-Json
    foreach ($p in $auth.profiles.PSObject.Properties) {
        if ($p.Value.PSObject.Properties.Name -contains 'key') { $p.Value.key = '' }
    }
    ($auth | ConvertTo-Json -Depth 20) | Set-Content $authFile -Encoding utf8
    Log '已清空 auth-profiles.json 中的 API key'
}

# 4. 经原生 CLI 一次性校验写入：关渠道/关 dreaming/关自动更新/收敛白名单/关 funnel
$patch = @'
{
  "update": { "auto": { "enabled": false }, "checkOnStart": false },
  "channels": {
    "telegram":   { "enabled": false, "allowFrom": [8320970051], "groupAllowFrom": [8320970051] },
    "feishu":     { "enabled": false },
    "googlechat": { "enabled": false }
  },
  "plugins": { "entries": { "memory-core": { "config": { "dreaming": { "enabled": false } } } } },
  "gateway": { "tailscale": { "mode": "off" } }
}
'@
$patchFile = Join-Path $logDir 'safe-mode.patch.json'
$patch | Set-Content $patchFile -Encoding utf8
& openclaw config patch --file $patchFile | ForEach-Object { Log "config: $_" }
Log '已将 openclaw.json 切到安全模式'

# 5. 关闭 Tailscale 公网暴露
if (Test-Path $ts) { & $ts serve reset 2>$null; Log 'tailscale serve/funnel 已复位' }

# 6. 重新拉起网关（安全模式，零花费），验证开机自启路径可用
Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8
$conn = Test-NetConnection 127.0.0.1 -Port 18789 -WarningAction SilentlyContinue
if ($conn.TcpTestSucceeded) { Log '[OK] 网关已在安全模式监听 18789（无 key，零花费）' }
else { Log '[WARN] 18789 暂未监听；心跳任务会在 15 分钟内重试' }

# 7. 状态标记
@{ state = 'disabled'; at = (Get-Date -Format o); backup = $backupDir } | ConvertTo-Json |
    Set-Content (Join-Path $logDir 'api-state.json') -Encoding utf8
Log '=== DISABLE 完成。需要使用时运行 enable-openclaw-api.ps1 恢复。 ==='
