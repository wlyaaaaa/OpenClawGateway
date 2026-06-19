<#
.SYNOPSIS
  从零 / 重装部署 OpenClaw 网关（含本仓库的全部优化）。
.DESCRIPTION
  两种模式：
    -RestoreFrom <备份目录>  ：从 backup-config.ps1 的私有备份**完整恢复**（含密钥，推荐）。
    （无 -RestoreFrom）       ：用仓库 bootstrap 模板**全新部署**，交互式填入密钥。
  执行内容：装运行时 → 还原/初始化配置 → 设网关密码 → 注册三个计划任务 → 装 Cline 全局规则。
.EXAMPLE
  # 重装后从私有备份完整恢复（最快）
  powershell -ExecutionPolicy Bypass -File .\bootstrap\setup.ps1 -RestoreFrom "D:\OpenClawBackup\full-20260619-220000"
.EXAMPLE
  # 全新机器、无备份
  powershell -ExecutionPolicy Bypass -File .\bootstrap\setup.ps1
.NOTES
  以管理员 PowerShell 运行。
#>
param(
    [string]$RestoreFrom,
    [string]$User = "$env:USERDOMAIN\$env:USERNAME"
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$OC   = Join-Path $env:USERPROFILE '.openclaw'
function Step($m){ Write-Host "`n=== $m ===" -ForegroundColor Green }
function Info($m){ Write-Host "  $m" -ForegroundColor DarkGray }
function Warn($m){ Write-Host "  ! $m" -ForegroundColor Yellow }

# 0. 管理员
$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) { throw '请以管理员 PowerShell 运行。' }

# 1. 运行时
Step '1/6 检查运行时 (Node / OpenClaw / Cline)'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Info '安装 Node.js LTS...'; winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements }
if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) { Info '全局安装 openclaw...'; npm install -g openclaw }
if (-not (Get-Command cline -ErrorAction SilentlyContinue)) { Info '全局安装 cline...'; npm install -g cline }
Info ('openclaw ' + (& openclaw --version))

# 2. 配置
Step '2/6 还原 / 初始化配置'
New-Item -ItemType Directory -Force $OC | Out-Null
if ($RestoreFrom) {
    if (-not (Test-Path $RestoreFrom)) { throw "备份目录不存在: $RestoreFrom" }
    Info "从私有备份完整恢复: $RestoreFrom"
    Get-ChildItem $RestoreFrom -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $OC $_.Name) -Force }
    $cred = Join-Path $RestoreFrom 'credentials'
    if (Test-Path $cred) { Copy-Item $cred (Join-Path $OC 'credentials') -Recurse -Force }
} else {
    Info '无备份：用仓库模板初始化（稍后需填密钥）'
    if (-not (Test-Path (Join-Path $OC 'openclaw.json'))) { & openclaw setup 2>$null | Out-Null }
    Copy-Item (Join-Path $PSScriptRoot 'openclaw.template.json') (Join-Path $OC 'openclaw.json') -Force
    Copy-Item (Join-Path $PSScriptRoot 'auth-profiles.template.json') (Join-Path $OC 'auth-profiles.json') -Force
    Warn '请编辑以下文件，把 <...> 占位符换成真实值：'
    Warn "  $OC\auth-profiles.json   (DashScope API key)"
    Warn "  $OC\openclaw.json        (telegram botToken / feishu appSecret / googlechat serviceAccount)"
    Warn '完成后再继续注册任务（或用 tools\set-api.ps1 填 key）。'
}

# 3. 网关密码（Machine 级）
Step '3/6 设置网关密码 (Machine 环境变量)'
$existing = [System.Environment]::GetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','Machine')
if ($existing) { Info '已存在 Machine 级密码，跳过。' }
else {
    $sec = Read-Host '输入网关密码 OPENCLAW_GATEWAY_PASSWORD' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Environment]::SetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD',$pw,'Machine')
    Info '已写入 Machine 级密码。'
}

# 4. gateway.cmd 堆上限（若缺失则由 daemon install 生成，再补堆参数）
Step '4/6 准备 gateway.cmd（服务启动文件）'
$gw = Join-Path $OC 'gateway.cmd'
if (-not (Test-Path $gw)) { Info '生成服务文件...'; & openclaw daemon install 2>$null | Out-Null }
if (Test-Path $gw) {
    $t = Get-Content $gw -Raw
    if ($t -notmatch 'max-old-space-size') { (Get-Content $gw) -replace 'node\.exe"', 'node.exe" --max-old-space-size=1536' | Set-Content $gw -Encoding ascii; Info '已加 1536MB 堆上限' }
}

# 5. 注册三个计划任务
Step '5/6 注册计划任务 (Gateway / Heartbeat / Update)'
& (Join-Path $repo 'openclaw_silent_boot_guardian.ps1')
$pr2 = New-ScheduledTaskPrincipal -UserId $User -LogonType S4U -RunLevel Highest
$hb = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$repo\openclaw_heartbeat.ps1`""
$hbT = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask 'OpenClaw Heartbeat' -Action $hb -Trigger $hbT -Principal $pr2 -Settings (New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable) -Force | Out-Null
$up = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$repo\openclaw_update.ps1`""
$upT = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
Register-ScheduledTask 'OpenClaw Update' -Action $up -Trigger $upT -Principal $pr2 -Settings (New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable) -Force | Out-Null
Info '三个任务已注册（Heartbeat/Update 默认启用，可按需 Disable）。'

# 6. Cline 全局规则
Step '6/6 安装 Cline 全局规则'
$rulesDst = Join-Path $env:USERPROFILE 'Documents\Cline\Rules'
New-Item -ItemType Directory -Force $rulesDst | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'cline-rules\openclaw-service.md') $rulesDst -Force
Info "已装到 $rulesDst"

Step '完成'
& openclaw config validate 2>&1 | Select-Object -First 3
Write-Host "`n下一步：" -ForegroundColor Green
Write-Host "  1) 若用模板部署，先填好 ~/.openclaw 的密钥占位符" -ForegroundColor Gray
Write-Host "  2) 运行  .\api.ps1 on   点亮机器人" -ForegroundColor Gray
Write-Host "  3) 运行  .\tools\status.ps1   核对状态" -ForegroundColor Gray
