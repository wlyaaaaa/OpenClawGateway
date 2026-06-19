# OpenClawGateway

Windows 11 上 **OpenClaw v2026.6.6** 个人智能体网关（昵称“小龙虾”）的运维脚本与文档。

> 本仓库只含**脚本与文档**，绝不包含任何密钥/令牌。真实凭据保存在本机
> `C:\Users\10979\.openclaw\`（已 gitignore）。文中 `<...>` 为占位符。

## 这是什么
OpenClaw 是常驻后台的个人智能体网关：统一接收 Telegram / 飞书 / Google Chat 消息，
驱动 Qwen（阿里云 DashScope）大模型完成任务，并可调用本机 Cline CLI 等工具。
本仓库解决三件事：

1. **静默开机自启** —— 系统引导即起、无黑窗、无需登录（计划任务 + S4U + VBS 包装）。
2. **心跳自愈** —— 每 15 分钟探测端口 18789，挂死自动重启。
3. **成本安全模式** —— 一键禁用 LLM API，杜绝无人值守烧钱；一键恢复。

## 快速开始
```powershell
# 1) 静默开机自启（管理员）
powershell -ExecutionPolicy Bypass -File .\openclaw_silent_boot_guardian.ps1

# 2) 进入安全模式（零 LLM 花费）
powershell -ExecutionPolicy Bypass -File .\disable-openclaw-api.ps1

# 3) 需要使用时恢复 API
powershell -ExecutionPolicy Bypass -File .\enable-openclaw-api.ps1
```

## 文件
| 文件 | 作用 |
|------|------|
| `openclaw_silent_boot_guardian.ps1` | 重注册“OpenClaw Gateway”计划任务为静默开机自启 |
| `openclaw_heartbeat.ps1` | 15 分钟端口看门狗，自愈重启 |
| `openclaw_update.ps1` | 全局升级 + 重启 + 健康检查 |
| `openclaw_run_hidden.vbs` | 零窗口启动包装器 |
| `openclaw_task.xml` | 计划任务定义备份 |
| `disable-openclaw-api.ps1` / `enable-openclaw-api.ps1` | 成本安全模式开关 |
| `docs/USAGE.md` | **日常使用与省钱指南** |
| `docs/OPENCLAW.md` | 运维手册 |
| `docs/AUDIT.md` | 深度审计报告 |
| `docs/HOW-TO-ENABLE.md` | 安全模式开关说明 |

## 计划任务（三个，均静默 S4U/Highest）
| 任务 | 触发 | 作用 |
|------|------|------|
| `OpenClaw Gateway` | 开机 +30s | 静默拉起网关 |
| `OpenClaw Heartbeat` | 每 15 分钟 | 端口看门狗，自愈重启 |
| `OpenClaw Update` | 每周日 04:00 | stable 通道自动更新（仅 npm，不阻塞开机） |

## 安全须知
- 渠道白名单 `allowFrom` 只放自己的 ID，切勿用 `"*"`。
- 常驻环境用 `stable` 更新通道（`openclaw update status` 查看）。
- 详见 [docs/OPENCLAW.md](docs/OPENCLAW.md) 与 [docs/AUDIT.md](docs/AUDIT.md)。

## 致谢
基于 [OpenClaw](https://docs.openclaw.ai) v2026.6.6 原生 `daemon` / `update` 机制构建。
