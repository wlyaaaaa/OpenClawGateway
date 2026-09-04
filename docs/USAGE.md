# 使用路径

本页既可由人阅读，也可直接交给 AI Agent（智能体）作为运维入口地图。通常由 AI 执行只读检查、选择安全脚本并解释回执；人不需要长期打开 OpenCode、CodeG 或 PowerShell。CodeG/Cline 只是一条可选接入，不是使用这个项目的前提。

## 1. 先看当前状态

```powershell
pwsh -NoProfile -File .\tools\status.ps1
pwsh -NoProfile -File .\api.ps1 status
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Json
```

AI 会读取并向你解释：OpenClaw 版本、Gateway RPC、配置、计划任务、默认模型、各 Provider 路由、渠道开关和 Funnel（外部 Tailscale 路由）状态。

状态解释：

- Gateway RPC/health 通过：当前网关可响应；
- 渠道 enabled：只代表配置打开，不代表消息已收发；
- route + auth configured：代表路线与认证存在，不代表远程调用成功；
- 默认 local：新会话通常从本地模型开始，不代表所有旧会话和计划任务都不会用远程模型；
- Update Disabled：是人工受控更新的正常状态，不是故障。

## 2. 从手机交办

在已经完成私人渠道配置的前提下，从 Telegram 或飞书发送任务。正常链路是：消息进入 Gateway、Agent 选择模型并执行、结果回到原渠道。

本公开仓库不包含机器人身份、白名单、token 或私人入口。若只看到 `enabled`，但没有真实入站和回发证据，应把渠道记为“已配置、未完成 E2E”。

## 3. 选择模型

使用 OpenClaw 官方命令查看和变更：

```powershell
openclaw models status --json
openclaw models list
openclaw models set <provider/model>
openclaw models auth list --json
```

模型状态不会输出 secret（秘密），但仍不要把账号标签或私人配置原文复制到公开报告。

`api.ps1 status` 是成本态势，不是开关。旧 `on/off/toggle` 已退役并返回退出码 2，因为它无法覆盖多来源认证、会话固定模型和全部远程路线。

## 4. Gateway 不健康

先运行只读检查：

```powershell
openclaw config validate --json
openclaw gateway status --require-rpc --json
openclaw health --json --verbose
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Json
```

只有确定需要重注册时，才在管理员 PowerShell 中显式执行：

```powershell
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Repair -Json
```

该动作会改变 Windows 常驻注册。默认不带 `-Repair` 时不会修改系统。

## 5. 备份与恢复演练

```powershell
$receipt = pwsh -NoProfile -File .\tools\backup-config.ps1 -Json | ConvertFrom-Json
pwsh -NoProfile -File .\tools\restore-config.ps1 `
  -From $receipt.backup_path `
  -Target <fresh-directory> `
  -Json
```

恢复结果中的 `activation_performed=false` 是正确状态：归档只被恢复到全新暂存目录，没有覆盖正在运行的 OpenClaw。

## 6. CodeG / Cline

运行 `tools/setup-codeg-bridge.ps1` 会保留 Cline 现有配置，只插入或更新 `openclaw-bridge`。之后仍需在 CodeG/Cline 中刷新、启用，并完成一次 MCP 初始化与工具列表回读；端口在线不能替代这一步。详见 [CODEG.md](CODEG.md)。
