# 部署与 bootstrap

## 前提

- Windows 10/11；
- PowerShell 7；
- Node.js 与 OpenClaw 由官方支持方式安装；
- 私人渠道和 Provider 凭据在本机私人配置中完成，不写入本仓库。

官方入口：

- [Gateway CLI](https://docs.openclaw.ai/cli/gateway)
- [Configuration](https://docs.openclaw.ai/configuration)
- [Models CLI](https://docs.openclaw.ai/cli/models)
- [Channels CLI](https://docs.openclaw.ai/cli/channels)
- [Backup CLI](https://docs.openclaw.ai/cli/backup)

## 公共模板

`bootstrap/openclaw.template.json` 是脱敏配置模板；旧 `auth-profiles.template.json` 已退役，模型认证只走官方 `openclaw models auth`：

- 消息渠道默认 disabled；
- allowlist 为空，不允许 `*`；
- Gateway 默认 loopback；
- dreaming 与自动更新默认关闭；
- 必填值保留显式占位符。

模板不预设 Gateway 认证方式或任何秘密。认证由私人 ConfigSource、OpenClaw 官方配置流程或 PCConfig 受控启动器完成。

`bootstrap/setup.ps1` 必须在任何安装、配置写入或任务注册之前检查占位符。占位未替换时应非零退出，不能打印“完成”。

## 安装流程

1. 把 `openclaw.template.json` 复制到私人工作位置；
2. 在私人副本中填入实际 workspace（工作区）、模型和渠道设置；
3. 用 `-WhatIf` 预演，确认候选 schema 与占位符检查通过；
4. 由 bootstrap 原子写入配置，并在后验失败时自动恢复旧配置；
5. 使用官方 `openclaw models auth` 完成私人模型认证；
6. 需要时显式注册 Gateway，再独立回读配置、RPC、health 和计划任务。

```powershell
pwsh -NoProfile -File .\bootstrap\setup.ps1 -ConfigSource <private-openclaw.json> -WhatIf
pwsh -NoProfile -File .\bootstrap\setup.ps1 -ConfigSource <private-openclaw.json>
openclaw models auth list --json
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Repair -Json
openclaw config validate --json
openclaw gateway status --require-rpc --json
openclaw health --json --verbose
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Json
```

## 从 disabled 模板到可收消息

公共模板故意把所有渠道关闭，也不保存 token。完成私人配置后，使用官方 guided setup（引导设置），不要把凭据写进本仓库或命令历史：

```powershell
openclaw channels list --all
openclaw channels add
openclaw channels status --probe
```

`channels status --probe` 只证明账户/连接探测。最终仍需从目标应用发送一条受控测试消息，并确认入站、Agent 执行与原渠道回发都成功，才算渠道 E2E（端到端）通过。

不要从公开模板推断本机账号、机器人 ID、私有 endpoint（端点）或 token。真实值由私人配置 Owner 管理。

## 验收层级

- 模板解析通过：只证明静态文件合法；
- setup 成功：证明安装脚本完成；
- Gateway RPC/health 通过：证明网关当前健康；
- 渠道消息 E2E：还需要一次真实入站与回发；
- 远程模型 Live（真实调用）：还需要一次可能付费的模型请求。

后两项不能由前面的测试替代。
