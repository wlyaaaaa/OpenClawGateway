# =====================================================================
#  setup-codeg-bridge.ps1 — 一键配置 codeg ↔ OpenClaw 接入
# ---------------------------------------------------------------------
#  背景（为什么是这条路）：
#   - codeg 的「OpenClaw」ACP agent 走不通：codeg 的 ACP 客户端在握手时
#     authenticate 步骤不完整、且始终发送 per-session mcpServers 字段，
#     而 OpenClaw 的 ACP 桥拒绝 per-session MCP —— 两端都无开关，codeg 侧 bug。
#   - 唯一可行：让 codeg 的「工作 agent」（Cline / Claude Code）通过
#     `openclaw-bridge` 这个 MCP 服务去调用 OpenClaw（openclaw mcp serve）。
#   - openclaw-bridge 连网关需要网关密码（gateway.auth.mode=password），
#     缺密码即报 "Authentication required: Call authenticate before creating a session"。
#
#  本脚本优先使用 PCConfig 的只读启动器，在子进程内临时注入凭据；
#  只有未安装该启动器的旧环境才兼容读取机器级环境变量。
#
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\setup-codeg-bridge.ps1
# =====================================================================
param(
    [string]$ClineSettingsPath = (
        Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
    ),
    [switch]$SkipProbe
)

$ErrorActionPreference = 'Stop'

$clineSettings = $ClineSettingsPath
$openclawCmd   = Join-Path $env:APPDATA "npm\openclaw.cmd"
$gatewayUrl    = "http://127.0.0.1:18789"
$managedPwsh   = 'C:\Program Files\PowerShell\7\pwsh.exe'
$managedLauncher = 'C:\ProgramData\PCConfig\SecretBroker\Start-OpenClawMcpBridge.ps1'

Write-Host "=== setup-codeg-bridge: 配置 openclaw-bridge MCP ==="

# 1) 选择凭据注入方式
$managedMode = (
    (Test-Path -LiteralPath $managedPwsh -PathType Leaf) -and
    (Test-Path -LiteralPath $managedLauncher -PathType Leaf)
)
$pw = $null
if ($managedMode) {
    Write-Host "[OK] 使用 PCConfig 受控启动器；Cline 配置不保存网关密码。"
}
else {
    $pw = [System.Environment]::GetEnvironmentVariable(
        'OPENCLAW_GATEWAY_PASSWORD',
        'Machine'
    )
    if ([string]::IsNullOrWhiteSpace($pw)) {
        Write-Host "[ERROR] 未找到 PCConfig 受控启动器，旧式机器级凭据也不存在。"
        Write-Host "        先完成 PCConfig Secret Broker 初始化，再重跑本脚本。"
        exit 1
    }
    Write-Host "[WARN] 正在使用旧式机器级环境变量兼容模式。"
}

# 2) openclaw.cmd 路径检查（旧模式需要；受控启动器自行验证）
if (-not (Test-Path $openclawCmd)) {
    Write-Host "[ERROR] 未找到 openclaw.cmd: $openclawCmd（openclaw 是否已全局安装？）"
    exit 1
}

# 3) 写 openclaw-bridge 到 Cline 生效配置（codeg 检测此文件）
$bridge = if ($managedMode) {
    [ordered]@{
        type = 'stdio'
        command = $managedPwsh
        args = @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $managedLauncher
        )
        env = [ordered]@{
            OPENCLAW_URL = $gatewayUrl
        }
    }
}
else {
    [ordered]@{
        type = 'stdio'
        command = $openclawCmd
        args = @('mcp', 'serve')
        env = [ordered]@{
            OPENCLAW_URL = $gatewayUrl
            OPENCLAW_GATEWAY_PASSWORD = $pw
        }
    }
}
$cfg = [ordered]@{
    mcpServers = [ordered]@{
        'openclaw-bridge' = $bridge
    }
}
$dir = Split-Path -Parent $clineSettings
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$json = $cfg | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($clineSettings, $json, (New-Object System.Text.UTF8Encoding($false)))
$writeMessage = if ($managedMode) {
    "[OK] 已写入无明文凭据的 openclaw-bridge 到:"
}
else {
    "[OK] 已写入旧式兼容 openclaw-bridge 到:"
}
Write-Host $writeMessage
Write-Host "     $clineSettings"

# 4) 自检：网关端口是否在线（openclaw mcp serve 是常驻 stdio 进程，不便在脚本里
#    可靠地驱动收尾；这里做轻量端口探活，完整认证可用下方手动命令验证）
if (-not $SkipProbe) {
    Write-Host "[..] 探活网关端口 18789 ..."
    try {
        $conn = Test-NetConnection -ComputerName '127.0.0.1' -Port 18789 -WarningAction SilentlyContinue
        if ($conn.TcpTestSucceeded) {
            Write-Host "[OK] 网关在线（18789）。openclaw-bridge 可由受控启动器完成认证。"
        } else {
            Write-Host "[WARN] 网关 18789 未响应。请确认 'OpenClaw Gateway' 计划任务已启动。"
        }
    } catch {
        Write-Host "[..] 端口探活跳过: $_"
    }
}
if ($managedMode) {
    Write-Host "    完整认证由受控启动器在子进程内完成，不需要手工粘贴密码。"
}
else {
    Write-Host "    当前为旧式兼容模式；建议完成 PCConfig Secret Broker 迁移。"
}

# 5) 收尾步骤（在 codeg 里）
Write-Host ""
$pw = $null
Write-Host "===== 在 codeg 里完成接入 ====="
Write-Host "1. codeg → 设置 → MCP → 点【刷新】（应出现 openclaw-bridge）"
Write-Host "2. 把 openclaw-bridge 的【启用应用】勾给 Cline（或 Claude Code）"
Write-Host "3. 用【Cline】这个 agent 发任务（切勿用「OpenClaw」ACP agent —— 被 codeg bug 堵死）"
Write-Host "4. Cline 即可调用 OpenClaw 对话工具：conversations_list / conversation_get /"
Write-Host "   messages_read / messages_send / events_poll / events_wait /"
Write-Host "   attachments_fetch / permissions_list_open / permissions_respond"
Write-Host ""
Write-Host "完成。"
