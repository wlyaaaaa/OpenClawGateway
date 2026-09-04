# OpenClawGateway

OpenClawGateway 是一个面向 Windows 的公开脱敏运维仓库：让 OpenClaw Gateway（网关）在电脑上稳定常驻，接收已经配置的消息渠道请求，选择本地或远程模型，并把结果送回原渠道。

它不是第二套聊天机器人、模型平台或凭据中心。OpenClaw 拥有模型、渠道与会话；PCConfig 可拥有本机凭据注入和受控启动；本仓库只保留能公开的状态、生命周期、更新、备份恢复和本地接入脚本。

## 一句话数据流

```text
Telegram / 飞书（Google Chat 可选）
            ↓
OpenClaw Gateway，默认只监听本机回环地址
            ↓
本地模型或明确选择的远程 Provider（提供方）
            ↓
结果回到原消息渠道
```

渠道显示为 enabled（已启用）只证明配置开关，不等于真实消息已收发；模型路由和认证存在也不等于远程模型调用成功。

## 当前脱敏观测

以下是 2026-09-03 的只读观测，不是永久配置承诺：

| 观察项 | 结果 |
|---|---|
| OpenClaw | `2026.8.1`，配置合法，Gateway RPC（网关远程调用）与健康检查通过 |
| 监听 | 单一 loopback（本机回环）监听者，端口 `18789` |
| 默认模型 | `ollama5090d/qwen3.8:27b`，属于本地路线 |
| 自动模型轴 | fallback（回退）为空，utility（辅助模型）与图像模型未配置；会话固定模型和 cron（定时任务）覆盖未核对 |
| 远程路线 | Qwen 11 条、DeepSeek 2 条、Z.AI 8 条；没有进行付费调用 |
| 渠道运行态 | Telegram `running/connected/ready`；飞书 `running/starting` 且未报告错误；两者都没有 lastInbound/lastOutbound 记录，本轮没有发送测试消息；Google Chat disabled |
| Funnel | active（活动），只确认存在外部 Tailscale 路由，不公开主机名或 URL |
| 插件 | Telegram、飞书、Qwen、Z.AI 均为 loaded（已加载）；版本标签并不完全相同，未把 loaded 冒充成真实调用通过 |
| Windows 常驻 | 当前 Gateway 运行健康；Heartbeat（心跳）最近结果为 0；Update（更新任务）按设计禁用自动执行 |
| 更新 | stable（稳定）通道目标为 `2026.9.1`，当前关系 `behind`（落后目标版）；本轮未升级或重启 |
| 备份 | 实际生成 224,287,339 字节官方归档，wrapper（包装脚本）与独立 `backup verify` 均通过；未做现役激活恢复 |
| OpenClaw doctor | 30 项执行、29 项跳过、3 条 warning（警告）：两条是未启用远程节点接入，一条是私人本机配置仍含 secret-bearing（承载秘密）字段；未公开任何值 |

Gateway 当前健康与计划任务的历史 `LastTaskResult` 是两种证据。现有 Gateway 任务曾留下非零历史回执，因此这里只确认当前 RPC/health（健康）通过，不把历史调度写成全绿。

## 常用入口

在仓库根目录使用 PowerShell 7：

```powershell
# 一屏查看版本、Gateway、计划任务、模型、渠道和 Funnel 状态
pwsh -NoProfile -File .\tools\status.ps1

# 只读查看成本态势；不会修改凭据、会话或网关
pwsh -NoProfile -File .\api.ps1 status
pwsh -NoProfile -File .\api.ps1 status -Json

# 只读核对 Windows 常驻状态；只有显式 -Repair 才重注册
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Json

# 只读查看稳定通道当前版与目标版
pwsh -NoProfile -File .\tools\managed-component.ps1 -Status -Json

# 创建 OpenClaw 官方校验归档
pwsh -NoProfile -File .\tools\backup-config.ps1 -Json

# 把归档恢复到全新暂存目录，不覆盖现役配置
pwsh -NoProfile -File .\tools\restore-config.ps1 -From <archive> -Target <fresh-directory> -Json
```

### 成本态势为什么不再有 `api on/off`

旧脚本只检查一个过期的文件档案，却忽略 OpenClaw 2.0 的 SQLite、环境变量、会话固定模型和多 Provider 路由，会在远程认证仍可用时错误显示 `API OFF`。它还直接停计划任务、强杀端口进程，并把“默认本地模型”冒充成全局零费用保证。

现在 `api.ps1 status` 只报告可验证事实，包括默认、fallback、utility、图像模型、远程可选路线与认证来源；它还明确声明没有核对会话和 cron 覆盖。旧 `on/off/toggle` 会以退出码 2 明确拒绝，不修改任何运行态。需要改变模型或认证时，使用 OpenClaw 官方 `models`、`models auth` 和 `config` 命令。详见 [OpenClaw Models](https://docs.openclaw.ai/models) 与 [Models CLI](https://docs.openclaw.ai/cli/models)。

## 产品边界

- `openclaw_heartbeat.ps1` 使用官方 Gateway 生命周期与健康回读，不把端口存在当成健康。
- `openclaw_silent_boot_guardian.ps1` 默认只读；修复优先走 PCConfig 受控启动器，没有该入口时走官方 `openclaw gateway install`，不再生成仓库内 VBS 或持久化网关密码。
- `openclaw_update.ps1` 是人工更新入口；自动更新任务保持 disabled。更新事务先备份，再调用官方更新，最后独立验证版本、配置、RPC、模型与任务。
- `backup-config.ps1` 只创建 OpenClaw 官方校验归档；`restore-config.ps1` 只恢复到全新暂存目录，绝不原地覆盖现役配置。
- 默认归档根是用户目录下的 `OpenClawBackups`，也可用 `OPENCLAW_BACKUP_DIR` 指定；它刻意位于 `.openclaw` 源状态目录之外。
- 完整离线激活只链接 [OpenClaw Backup CLI](https://docs.openclaw.ai/cli/backup) 的官方流程；本轮未停 Gateway、未替换现役状态，也未把 staging（暂存）成功写成恢复完成。
- `setup-codeg-bridge.ps1` 只向 Cline 配置中 upsert（插入或更新）`openclaw-bridge`，保留其他 MCP Server（模型上下文协议服务）；端口在线不等于真实 MCP 认证和工具调用成功。
- 机器上的私人状态备份拓扑是 3 个 Windows 计划任务承载 4 个消费者，但分属两个 Owner（负责人）：独立 `codex-memory` 项目拥有 20:05/22:05 的 Codex 任务；本仓库只拥有 20:10/22:10 的 Gemini 任务，以及 20:20/22:20 先 Claude、后 OpenClaw 的共享任务。共享任务两段都会运行，最后传播第一段非零，否则传播第二段结果。本仓库不再保留无生产消费者的 Codex 脚本副本。
- WeFlow 的机器专用查询残件、旧模型注册脚本和无关个人静态站已经退役；它们不属于这个产品的公开能力。

## 文档

- [使用路径](docs/USAGE.md)
- [架构与边界](docs/OPENCLAW.md)
- [部署与 bootstrap（引导安装）](docs/DEPLOY.md)
- [维护、更新与恢复](docs/MAINTENANCE.md)
- [脚本清单](docs/SCRIPTS.md)
- [CodeG / Cline MCP 接入](docs/CODEG.md)

## 测试

测试必须使用隔离临时目录；不会发送消息、调用付费模型、更新运行时或覆盖真实配置。

```powershell
pwsh -NoProfile -File .\tools\test-api-status.ps1
pwsh -NoProfile -File .\tools\test-bootstrap.ps1
pwsh -NoProfile -File .\tools\test-codeg-bridge.ps1
pwsh -NoProfile -File .\tools\test_common.ps1
pwsh -NoProfile -File .\tools\test_backup_config.ps1
pwsh -NoProfile -File .\tools\test_restore_config.ps1
pwsh -NoProfile -File .\tools\test_update_lib.ps1
pwsh -NoProfile -File .\tools\test-git-cloud-sync.ps1
pwsh -NoProfile -File .\tools\test-public-safe-policy.ps1
```

`tools/test_managed_component.ps1` 使用 Pester 6 运行更新状态机的隔离夹具。测试通过只证明脚本合同，不替代真实安装、运行、发布或消息 E2E（端到端）验收。

## 公开仓库边界

本仓库不保存 token、API key、Gateway 密码、账号标识、私有端点、原始消息、完整运行日志或恢复快照。完整私人恢复材料由私人备份 Owner 管理；公开文档只描述角色，不复制其内容。
