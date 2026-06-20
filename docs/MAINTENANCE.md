# 维护与部署指南

> 适用：Windows 11 + OpenClaw v2026.6.8（npm 全局安装）+ DashScope/Qwen。
> 配置目录：`C:\Users\10979\.openclaw\`（含密钥，永不入库）。

## 1. 全新部署（装机 / 重装系统后）
```powershell
# 1) 运行时
winget install OpenJS.NodeJS.LTS
npm install -g openclaw

# 2) 还原配置与密钥（二选一）
#    a. 有备份：把备份的 .openclaw 还原回 C:\Users\10979\.openclaw\
.\tools\restore-config.ps1 -From <备份目录>
#    b. 无备份：openclaw onboard / openclaw configure 重新引导

# 3) 网关密码（Machine 级，S4U 早期可读）
[System.Environment]::SetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','<password>','Machine')

# 4) 注册静默开机自启
powershell -ExecutionPolicy Bypass -File .\openclaw_silent_boot_guardian.ps1

# 5)（可选）重建心跳/更新任务 —— 见第 3 节
```

## 2. 计划任务一览
| 任务 | 触发 | 脚本 | 状态控制 |
|------|------|------|----------|
| `OpenClaw Gateway` | 开机 +30s | VBS→gateway.cmd | 开机自启，常驻启用 (Ready) |
| `OpenClaw Heartbeat` | 每 15 分钟 | openclaw_heartbeat.ps1 | 端口看门狗 (Ready) |
| `OpenClaw Update` | 每周 04:00 | openclaw_update.ps1 | 自动更新，**Disabled（故意，改用脚本手动+自愈）** |
| `OpenClawGateway AutoPush` | 每日 | tools\auto-archive-push.ps1 | 归档+机密扫描后推 GitHub (Ready) |
| `OpenClaw Memory Backup` | 每日 **04:00 + 13:00** | tools\backup-memory.ps1 | 备份 Claude 记忆到本地(轮换30份，gitignore) (Ready) |

```powershell
# 查看
Get-ScheduledTask -TaskName 'OpenClaw *' | ft TaskName,State
# 暂停 / 恢复（“歇一歇自动任务”）
Disable-ScheduledTask -TaskName 'OpenClaw Heartbeat'
Enable-ScheduledTask  -TaskName 'OpenClaw Heartbeat'
# 手动启停网关
Stop-ScheduledTask -TaskName 'OpenClaw Gateway'; Start-ScheduledTask -TaskName 'OpenClaw Gateway'
```

## 3. 重建心跳 / 更新任务（如缺失）
```powershell
# 心跳（每 15 分钟）
$a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "E:\OpenClawGateway\openclaw_heartbeat.ps1"'
$t=New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
$pr=New-ScheduledTaskPrincipal -UserId 'WLY\10979' -LogonType S4U -RunLevel Highest
Register-ScheduledTask 'OpenClaw Heartbeat' -Action $a -Trigger $t -Principal $pr -Settings (New-ScheduledTaskSettingsSet -Hidden) -Force

# 更新（每周日 04:00）
$au=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "E:\OpenClawGateway\openclaw_update.ps1"'
$tu=New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
Register-ScheduledTask 'OpenClaw Update' -Action $au -Trigger $tu -Principal $pr -Settings (New-ScheduledTaskSettingsSet -Hidden) -Force
```

## 4. 更新机制
- 通道：`openclaw config get update.channel`（推荐 **stable**）。`checkOnStart=false`（避免开机
  早期 registry 超时拖崩，这是历史崩溃根因）。
- 自动：`OpenClaw Update` 任务每周执行 `npm install -g openclaw@<tag>`，**不跑 doctor**，重启网关。
- 手动：`.\openclaw_update.ps1` 或原生 `openclaw update --yes`（注意原生会跑 doctor，可能重写 gateway.cmd）。

## 5. 备份策略
```powershell
.\tools\backup-config.ps1                 # 配置 + 密钥 + credentials
.\tools\backup-memory.ps1                 # Claude 记忆（计划任务每日 04:00+13:00 自动跑）
```
重点备份：`openclaw.json`、`auth-profiles.json`、`config.yml`、`.env`、`credentials\`、`gateway.cmd`。
记忆备份双保险：①本地 `memory-backup\<时间戳>\`（gitignore，留 30 份）②私有云仓库 **`wlyaaaaa/claude-memory`**（已脱敏，本地工作目录 `E:\ClaudeMemoryBackup`）。计划任务每日 04:00+13:00 自动两者都做。

### 5.1 新电脑转移（从 GitHub）
```powershell
# 1) 运维体系
git clone https://github.com/wlyaaaaa/OpenClawGateway.git E:\OpenClawGateway
E:\OpenClawGateway\bootstrap\setup.ps1 -RestoreFrom "<你的私有备份目录>"
# 2) Claude 记忆（私有仓库）
git clone https://github.com/wlyaaaaa/claude-memory.git E:\ClaudeMemoryBackup
Copy-Item E:\ClaudeMemoryBackup\*.md "C:\Users\10979\.claude\projects\E--RamdiskGuardian\memory\" -Force
```
脚本/文档/模板随公开 git 来；**密钥**从你的私有备份还原（`auth-profiles.json`/`.env`/`config.yml`）；**记忆**从私有 `claude-memory` 仓库拉。详见 [DEPLOY.md](DEPLOY.md)。

## 6. 故障排查
| 现象 | 排查 |
|------|------|
| 端口 18789 无响应 | `.\tools\status.ps1`；`Get-Content ...\.openclaw\gateway.log -Tail 50` |
| 开机不自启 | 确认 `OpenClaw Gateway` 任务非 `Disabled`；重跑 boot guardian |
| 大模型不回 / 报错 | `.\tools\status.ps1` 看 API 模式（是否安全模式 key 空）；`openclaw status` |
| context overflow 崩溃 | 聊天里 `/new` 重置会话；见 USAGE |
| 启动慢 / registry 超时 | 确认 `checkOnStart=false`；本地代理是否就绪 |
| 网关 OOM 崩溃 | `gateway.cmd` 已设 `--max-old-space-size=1536`，可再调高 |
| codeg 里 OpenClaw 报 `Authentication required` | openclaw-bridge MCP 没带网关密码 → 跑 `tools\setup-codeg-bridge.ps1`；见 [CODEG.md](CODEG.md) |
| codeg 里 OpenClaw 报 `per-session MCP servers` | 用了 OpenClaw ACP agent（codeg bug）→ 改用 Cline agent + openclaw-bridge MCP |

常用诊断：`openclaw doctor`、`openclaw daemon status`、`openclaw status`、`openclaw health`。

## 8. codeg 控制台接入（详见 CODEG.md）
codeg 的 OpenClaw ACP agent 走不通；用 **Cline + openclaw-bridge MCP（带网关密码）** 间接调用 OpenClaw。
一键：`powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\tools\setup-codeg-bridge.ps1`。

## 7. 卸载
```powershell
Get-ScheduledTask 'OpenClaw *' | Unregister-ScheduledTask -Confirm:$false
openclaw uninstall          # 卸载服务 + 本地数据（CLI 仍在）
npm uninstall -g openclaw   # 彻底移除
```
