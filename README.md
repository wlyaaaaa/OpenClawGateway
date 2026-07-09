<div align="center">

# 🦞 OpenClawGateway

**Windows 11 上 OpenClaw v2026.6.8 个人智能体网关的运维工具集**

静默开机自启 · 心跳自愈 · 手动受控更新 · 成本安全模式 · 模型/提供方一键切换

</div>

> 本仓库只含**脚本与文档**，绝不包含任何密钥/令牌。真实凭据保存在本机
> `C:\Users\<USER>\.openclaw\`。文中 `<...>` 为占位符。

## 这是什么
OpenClaw（昵称“小龙虾”）是常驻后台的个人智能体网关：统一接收 Telegram / 飞书 /
Google Chat 消息，驱动 **Qwen（阿里云 DashScope）** 大模型完成任务，并可调用本机 Cline CLI 等工具。
本仓库把它的部署、自启、更新、成本、配置切换全部脚本化与文档化。

## ✨ 能力
- **静默开机自启**：系统引导即起，无黑窗、无需登录（计划任务 + S4U + VBS）。
- **心跳自愈**：每 15 分钟探测端口，挂死自动重启。
- **手动受控更新**：保留 `openclaw_update.ps1`，但 `OpenClaw Update` 任务默认 Disabled，避免无人审计升级改坏配置。
- **成本安全模式**：一键禁用 LLM API（清空 key）→ 零花费；一键恢复。
- **配置助手**：`switch-model` / `set-provider` / `set-thinking` / `backup` / `status`，
  应对“新模型上线、换 API、换 Key、换提供方”。

## 🚀 快速开始
```powershell
.\api.ps1 status                          # 状态一屏看全
.\api.ps1 on                              # 开启 API（机器人可用）
.\api.ps1 off                             # 闲时回到零花费

.\set-api.ps1 -Show                       # 看当前 key/模型/网站
.\set-api.ps1 -Model <新模型id>           # 换模型（新版本上线时）
.\set-api.ps1 -Profile deepseek           # 一键切到已存档的提供方
```

## 🗂 仓库结构
```
api.ps1                             ★一键开关 API（on/off/toggle/status）
set-api.ps1                         ★快速设 key/模型/网站 + 提供方档案
openclaw_silent_boot_guardian.ps1   静默开机自启重注册
openclaw_heartbeat.ps1              端口看门狗（计划任务调用）
openclaw_update.ps1                 通道感知手动更新（任务默认 Disabled）
openclaw_run_hidden.vbs             零窗口启动包装器
disable/enable-openclaw-api.ps1     安全模式引擎（被 api.ps1 调用）
bootstrap\                          从零部署：setup.ps1 + 脱敏配置模板 + Cline 规则
tools\                              配置助手（模型/思考/备份/状态/setup-codeg-bridge）
docs\                              文档（见下）
```

## ♻️ 重装恢复（一句话）
```powershell
git clone https://github.com/wlyaaaaa/OpenClawGateway.git E:\Projects\Tools\OpenClawGateway
E:\Projects\Tools\OpenClawGateway\bootstrap\setup.ps1 -RestoreFrom "<你的私有备份目录>"
```
详见 [docs/DEPLOY.md](docs/DEPLOY.md)。**记得定期 `tools\backup-config.ps1` 并异地保存备份。**

## 📚 文档
| 文档 | 内容 |
|------|------|
| [docs/DEPLOY.md](docs/DEPLOY.md) | **从零 / 重装部署**：一键 `bootstrap\setup.ps1` 全流程 |
| [docs/USAGE.md](docs/USAGE.md) | 日常使用：模型/思考、斜杠命令、手机 ChatOps |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | 脚本使用指南（逐个参数 + 示例） |
| [docs/MAINTENANCE.md](docs/MAINTENANCE.md) | 部署 / 计划任务 / 更新 / 备份 / 故障排查 |
| [docs/OPENCLAW.md](docs/OPENCLAW.md) | 架构与原理 |
| [docs/CODEG.md](docs/CODEG.md) | **codeg 控制台接 OpenClaw / Cline**（openclaw-bridge MCP） |
| [docs/AUDIT.md](docs/AUDIT.md) | 深度审计记录 |

## ⚙️ 当前状态（参考）
- 版本 v2026.6.10（stable）｜ 默认模型 `qwen3.7-plus` + 思考 `max`（最高）
- 网关 loopback:18789，堆 1536MB｜ API：**已启用（ON）**，闲时 `api.ps1 off` 回零花费
- 计划任务：`OpenClaw Gateway`(自启)、`Heartbeat`(15min)、`AutoPush`(每日) 均 **Ready**；
  `OpenClaw Update` **Disabled**（故意，改用 `openclaw_update.ps1` 手动+自愈，避免原生 doctor 改坏配置）

## 🔐 安全须知
- 渠道白名单 `allowFrom` 只放自己的 ID，切勿用 `"*"`。
- 凭据和本地备份只在 `C:\Users\<USER>\.openclaw\` 或私有备份仓库，公开仓库不保存真实 secrets、运行日志或记忆快照。

---
基于 [OpenClaw](https://docs.openclaw.ai) v2026.6.10 原生 `daemon` / `update` 机制构建。
