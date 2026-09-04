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
#  本脚本只接受 PCConfig 受控启动器，在子进程内临时注入凭据；
#  不把网关密码复制到 Cline 配置或命令行。
#
#  用法：powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\setup-codeg-bridge.ps1
# =====================================================================
param(
    [string]$ClineSettingsPath = (
        Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
    ),
    [switch]$SkipProbe,
    [string]$ManagedPwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe',
    [string]$ManagedLauncherPath = 'C:\ProgramData\PCConfig\SecretBroker\Start-OpenClawMcpBridge.ps1',
    [string]$GatewayUrl = 'http://127.0.0.1:18789'
)

$ErrorActionPreference = 'Stop'

$clineSettings = $ClineSettingsPath
$gatewayUrl = $GatewayUrl
$managedPwsh = $ManagedPwshPath
$managedLauncher = $ManagedLauncherPath

function ConvertTo-BridgeJson {
    param([Parameter(Mandatory)]$Value)

    return ($Value | ConvertTo-Json -Depth 64)
}

function Test-BridgeJsonEqual {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual
    )

    return ((ConvertTo-BridgeJson $Expected) -eq (ConvertTo-BridgeJson $Actual))
}

function Test-BridgeByteArrayEqual {
    param(
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][byte[]]$Actual
    )

    if ($Expected.Length -ne $Actual.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) {
            return $false
        }
    }

    return $true
}

function Read-ClineConfig {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $text = [System.IO.File]::ReadAllText($Path)
        $config = $text | ConvertFrom-Json
    }
    catch {
        throw "Cline MCP 配置不是可解析的 JSON，未修改原文件: $Path`n$($_.Exception.Message)"
    }

    if (-not ($config -is [pscustomobject])) {
        throw "Cline MCP 配置根节点必须是 JSON 对象，未修改原文件: $Path"
    }

    return $config
}

function Write-Utf8NoBomAtomically {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = Join-Path $directory (
        '.{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($Path), [Guid]::NewGuid().ToString('N')
    )
    $replaceBackupPath = "$tempPath.replace.bak"
    try {
        [System.IO.File]::WriteAllBytes($tempPath, $Bytes)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $Path, $replaceBackupPath)
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if (Test-Path -LiteralPath $replaceBackupPath -PathType Leaf) {
            Remove-Item -LiteralPath $replaceBackupPath -Force
        }
    }
}

function New-ClineRecoveryBackup {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $backupPath = "$Path.openclaw-bridge.bak"
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        return $backupPath
    }

    try {
        $stream = [System.IO.File]::Open(
            $backupPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.IOException] {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw
        }
    }

    return $backupPath
}

Write-Host "=== setup-codeg-bridge: 配置 openclaw-bridge MCP ==="

# 1) 选择凭据注入方式
$managedMode = (
    (Test-Path -LiteralPath $managedPwsh -PathType Leaf) -and
    (Test-Path -LiteralPath $managedLauncher -PathType Leaf)
)
if (-not $managedMode) {
    Write-Host "[ERROR] 未找到 PCConfig 受控启动器。"
    Write-Host "        先完成 PCConfig Secret Broker 初始化，再重跑本脚本。"
    exit 1
}
Write-Host "[OK] 使用 PCConfig 受控启动器；Cline 配置不保存网关密码。"

# 2) 写 openclaw-bridge 到 Cline 生效配置（codeg 检测此文件）
$bridge = [ordered]@{
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

$settingsExists = Test-Path -LiteralPath $clineSettings
if ($settingsExists -and -not (Test-Path -LiteralPath $clineSettings -PathType Leaf)) {
    throw "Cline MCP 配置路径不是普通文件: $clineSettings"
}

$existingBytes = $null
if ($settingsExists) {
    $existingBytes = [System.IO.File]::ReadAllBytes($clineSettings)
    $cfg = Read-ClineConfig -Path $clineSettings
}
else {
    $cfg = [pscustomobject]@{}
}

if ($null -ne $cfg.PSObject.Properties['mcpServers']) {
    $mcpServers = $cfg.PSObject.Properties['mcpServers'].Value
    if (-not ($mcpServers -is [pscustomobject])) {
        throw "Cline MCP 配置的 mcpServers 必须是 JSON 对象，未修改原文件: $clineSettings"
    }
}
else {
    $mcpServers = [pscustomobject]@{}
    $cfg | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value $mcpServers
}
$mcpServers | Add-Member -MemberType NoteProperty -Name 'openclaw-bridge' -Value $bridge -Force

$json = ConvertTo-BridgeJson $cfg
try {
    $candidateConfig = $json | ConvertFrom-Json
}
catch {
    throw "生成的 Cline MCP 候选 JSON 无法解析，未修改原文件: $($_.Exception.Message)"
}
if (-not ($candidateConfig -is [pscustomobject])) {
    throw '生成的 Cline MCP 候选 JSON 根节点不是对象，未修改原文件。'
}
$candidateMcpServers = $candidateConfig.PSObject.Properties['mcpServers'].Value
if (-not ($candidateMcpServers -is [pscustomobject]) -or
    $null -eq $candidateMcpServers.PSObject.Properties['openclaw-bridge'] -or
    -not (Test-BridgeJsonEqual $bridge $candidateMcpServers.PSObject.Properties['openclaw-bridge'].Value)) {
    throw '生成的 Cline MCP 候选 JSON 未包含精确的 openclaw-bridge，未修改原文件。'
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$candidateBytes = $utf8NoBom.GetBytes($json)
$backupPath = $null
if ($settingsExists) {
    $backupPath = New-ClineRecoveryBackup -Path $clineSettings -Bytes $existingBytes
}

$didWrite = -not $settingsExists -or -not (Test-BridgeByteArrayEqual -Expected $existingBytes -Actual $candidateBytes)
if ($didWrite) {
    Write-Utf8NoBomAtomically -Path $clineSettings -Bytes $candidateBytes
}

$writtenBytes = [System.IO.File]::ReadAllBytes($clineSettings)
if ($writtenBytes.Length -ge 3 -and
    $writtenBytes[0] -eq 0xEF -and $writtenBytes[1] -eq 0xBB -and $writtenBytes[2] -eq 0xBF) {
    throw "Cline MCP 配置写入后不是 UTF-8 无 BOM: $clineSettings"
}
$writtenConfig = Read-ClineConfig -Path $clineSettings
if (-not (Test-BridgeJsonEqual $candidateConfig $writtenConfig)) {
    throw "Cline MCP 配置写后回读未保留原有键或其他 MCP 服务: $clineSettings"
}
$writtenMcpServers = $writtenConfig.PSObject.Properties['mcpServers'].Value
if (-not ($writtenMcpServers -is [pscustomobject]) -or
    $null -eq $writtenMcpServers.PSObject.Properties['openclaw-bridge'] -or
    -not (Test-BridgeJsonEqual $bridge $writtenMcpServers.PSObject.Properties['openclaw-bridge'].Value)) {
    throw "Cline MCP 配置写后回读缺少精确的 openclaw-bridge: $clineSettings"
}

$writeMessage = "[OK] 已确认无明文凭据的 openclaw-bridge 到:"
Write-Host $writeMessage
Write-Host "     $clineSettings"
if ($backupPath) {
    Write-Host "     恢复备份: $backupPath"
}

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
Write-Host "    完整认证由受控启动器在子进程内完成，不需要手工粘贴密码。"

# 5) 收尾步骤（在 codeg 里）
Write-Host ""
Write-Host "===== 在 codeg 里完成接入 ====="
Write-Host "1. codeg → 设置 → MCP → 点【刷新】（应出现 openclaw-bridge）"
Write-Host "2. 把 openclaw-bridge 的【启用应用】勾给 Cline（或 Claude Code）"
Write-Host "3. 用【Cline】这个 agent 发任务（切勿用「OpenClaw」ACP agent —— 被 codeg bug 堵死）"
Write-Host "4. 等 MCP initialize 与 tools/list 实际通过后，Cline 才可调用对话工具："
Write-Host "   conversations_list / conversation_get /"
Write-Host "   messages_read / messages_send / events_poll / events_wait /"
Write-Host "   attachments_fetch / permissions_list_open / permissions_respond"
Write-Host ""
Write-Host "完成。"
