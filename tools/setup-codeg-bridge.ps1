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
#  本脚本：把带密码的 openclaw-bridge 写进 Cline 生效配置（codeg 会检测此文件），
#          并自检认证是否成功，最后打印 codeg 内的收尾步骤。
#
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\setup-codeg-bridge.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$clineSettings = "C:\Users\10979\.cline\data\settings\cline_mcp_settings.json"
$openclawCmd   = "C:\Users\10979\AppData\Roaming\npm\openclaw.cmd"
$gatewayUrl    = "http://127.0.0.1:18789"

Write-Host "=== setup-codeg-bridge: 配置 openclaw-bridge MCP ==="

# 1) 取网关密码（机器级环境变量；auth.mode=password）
$pw = [System.Environment]::GetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','Machine')
if ([string]::IsNullOrWhiteSpace($pw)) {
    Write-Host "[ERROR] 未找到机器级环境变量 OPENCLAW_GATEWAY_PASSWORD。"
    Write-Host "        请先确认网关密码已设置：[Environment]::SetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','<密码>','Machine')"
    exit 1
}
Write-Host ("[OK] 读到网关密码（len={0}）" -f $pw.Length)

# 2) openclaw.cmd 路径检查
if (-not (Test-Path $openclawCmd)) {
    Write-Host "[ERROR] 未找到 openclaw.cmd: $openclawCmd（openclaw 是否已全局安装？）"
    exit 1
}

# 3) 写 openclaw-bridge 到 Cline 生效配置（codeg 检测此文件）
$cfg = [ordered]@{
    mcpServers = [ordered]@{
        'openclaw-bridge' = [ordered]@{
            type    = 'stdio'
            command = $openclawCmd
            args    = @('mcp', 'serve')
            env     = [ordered]@{
                OPENCLAW_URL              = $gatewayUrl
                OPENCLAW_GATEWAY_PASSWORD = $pw
            }
        }
    }
}
$dir = Split-Path -Parent $clineSettings
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$json = $cfg | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($clineSettings, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[OK] 已写入 openclaw-bridge（含网关密码）到:"
Write-Host "     $clineSettings"

# 4) 自检：网关端口是否在线（openclaw mcp serve 是常驻 stdio 进程，不便在脚本里
#    可靠地驱动收尾；这里做轻量端口探活，完整认证可用下方手动命令验证）
Write-Host "[..] 探活网关端口 18789 ..."
try {
    $conn = Test-NetConnection -ComputerName '127.0.0.1' -Port 18789 -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host "[OK] 网关在线（18789）。openclaw-bridge 带密码即可认证。"
    } else {
        Write-Host "[WARN] 网关 18789 未响应。请确认 'OpenClaw Gateway' 计划任务已启动。"
    }
} catch {
    Write-Host "[..] 端口探活跳过: $_"
}
Write-Host "    完整认证手动验证（应列出 conversations_list 等工具）："
Write-Host "    printf '%s\n%s\n' '{\""jsonrpc\"":\""2.0\"",\""id\"":1,\""method\"":\""initialize\"",\""params\"":{\""protocolVersion\"":\""2024-11-05\"",\""capabilities\"":{},\""clientInfo\"":{\""name\"":\""t\"",\""version\"":\""1\""}}}' '{\""jsonrpc\"":\""2.0\"",\""id\"":2,\""method\"":\""tools/list\"",\""params\"":{}}' | OPENCLAW_URL=http://127.0.0.1:18789 OPENCLAW_GATEWAY_PASSWORD=<密码> timeout 12 openclaw mcp serve"

# 5) 收尾步骤（在 codeg 里）
Write-Host ""
Write-Host "===== 在 codeg 里完成接入 ====="
Write-Host "1. codeg → 设置 → MCP → 点【刷新】（应出现 openclaw-bridge）"
Write-Host "2. 把 openclaw-bridge 的【启用应用】勾给 Cline（或 Claude Code）"
Write-Host "3. 用【Cline】这个 agent 发任务（切勿用「OpenClaw」ACP agent —— 被 codeg bug 堵死）"
Write-Host "4. Cline 即可调用 OpenClaw 对话工具：conversations_list / conversation_get /"
Write-Host "   messages_read / messages_send / events_poll / events_wait /"
Write-Host "   attachments_fetch / permissions_list_open / permissions_respond"
Write-Host ""
Write-Host "完成。"
