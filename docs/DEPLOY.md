# 从零 / 重装部署指南

> 目标：在**全新或重装的 Windows 11** 上，从 GitHub 拉下本仓库，把整套 OpenClaw 网关
> （含本仓库的全部优化）**从零重建**。配置目录 `C:\Users\<你>\.openclaw\`。

---

## 0. 先决条件 & 心智模型
部署 = **公开仓库（脚本+模板+文档）** + **私有密钥（你自己保管）** 的组合：
- **公开可拉取**：本仓库的脚本、脱敏配置模板、文档。
- **私有不可入库**：DashScope API key、网关密码、Telegram botToken、飞书 appSecret、
  Google 服务账号 —— 这些只在你本机 `.openclaw\`，靠**你自己的备份**恢复。

> ⚠️ **现在就做的事（防患未然）**：定期运行 `.\tools\backup-config.ps1`，把
> `C:\Users\<USER>\.openclaw\secrets-backup\full-*` 整个目录**异地保存**（U 盘 / 私有网盘）。重装时这份备份 = 满血复活。

---

## 1. 一键部署（推荐）
管理员 PowerShell：
```powershell
git clone https://github.com/wlyaaaaa/OpenClawGateway.git E:\Projects\Tools\OpenClawGateway
cd E:\Projects\Tools\OpenClawGateway

# 模式 A：有私有备份（最快，含密钥）
.\bootstrap\setup.ps1 -RestoreFrom "D:\OpenClawBackup\full-20260619-220000"

# 模式 B：全新、无备份（用模板，过程中交互填密钥）
.\bootstrap\setup.ps1
```
`setup.ps1` 会依次：装运行时(Node/openclaw/cline) → 还原/初始化配置 → 设网关密码 →
生成 gateway.cmd 作为本地配置参考 → 注册 Gateway/Heartbeat；`OpenClaw Update` 任务保留但 Disabled → 装 Cline 全局规则 → 校验。

完成后：
```powershell
.\api.ps1 on            # 点亮机器人
.\tools\status.ps1      # 核对状态
```

---

## 2. 手动部署（理解每一步）
```powershell
# (1) 运行时
winget install OpenJS.NodeJS.LTS
npm install -g openclaw cline

# (2) 配置：二选一
#   A. 有备份：还原回 ~/.openclaw
.\tools\restore-config.ps1 -From "D:\OpenClawBackup\full-..."
#   B. 无备份：用模板
copy bootstrap\openclaw.template.json        $env:USERPROFILE\.openclaw\openclaw.json
copy bootstrap\auth-profiles.template.json   $env:USERPROFILE\.openclaw\auth-profiles.json
#      然后把两个文件里的 <...> 占位符换成真实密钥

# (3) 网关密码（Machine 级，S4U 早期可读）
[System.Environment]::SetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','<密码>','Machine')

# (4) 静默开机自启 + 心跳 + 更新任务
.\openclaw_silent_boot_guardian.ps1
#   （心跳/更新任务的注册命令见 MAINTENANCE.md 第 3 节，或直接用 setup.ps1）

# (5) Cline 全局规则
copy bootstrap\cline-rules\openclaw-service.md  $env:USERPROFILE\Documents\Cline\Rules\

# (6) 点亮
.\api.ps1 on
```

---

## 3. 密钥清单（填占位符时对照）
| 占位符 | 含义 | 哪里拿 |
|--------|------|--------|
| `<DASHSCOPE_API_KEY>` | 阿里云百炼 API key | 百炼控制台 → API-KEY |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关登录密码 | 你自定义 |
| `<TELEGRAM_BOT_TOKEN>` | Telegram 机器人 token | BotFather `/mybots → API Token` |
| `<FEISHU_APP_SECRET>` | 飞书应用密钥 | 飞书开放平台 → 凭证 |
| `<GOOGLE_SERVICE_ACCOUNT_JSON_ONE_LINE>` | Google Chat 服务账号 | GCP → 服务账号 JSON（转单行） |

> 用 `tools\set-api.ps1 -Key <key>` 可快速填 DashScope key（避免手改 JSON）。

---

## 4. 这套部署内置的优化（重装后自动带上）
模板 `bootstrap/openclaw.template.json` 已固化以下优化，重装即恢复：
- **默认模型** `qwen3.7-max`（最强）+ **`thinkingDefault: adaptive`**（分级预算，难题拉满、闲聊降档省 token）
- **`contextPruning: {mode: cache-ttl, ttl: 5m}`** —— 自动裁剪累积的旧工具输出，对话质量无损（官方 session-pruning，纯省 token）
- 模型名已修复（无乱码）、移除失效 gemini 选项；`runRetries.max=5`（减少无效重试烧 token）
- **更新通道 stable** + `checkOnStart=false`（开机不被 registry 超时拖崩）
- `OpenClaw Gateway` 计划任务 direct-node 参数带 `--max-old-space-size=1536`（防 OOM）
- 渠道默认收敛白名单（无 `"*"`）

### 4.1 工具联动（skills 触发式联想）
重装后由 `setup.ps1` 安装到工作区 `skills/`，让主脑**自动联想**正确工具：
- `🦞 cline-coding` —— 提到**写/改/调试代码、多文件、构建功能** → 委托本机 Cline（便宜模型 + diffs-only，省 token）
- `💬 wechat` —— 提到**微信/群消息/私聊/朋友圈** → 调本机 WeFlow API 读消息（此 skill 含本机隐私用法，**不入公开仓库**，重装从私有备份恢复）

### 4.2 可选进阶优化（需有付费 API 实跑验证后再开）
- **Prompt 缓存**：`agents.defaults.params.cacheRetention: "long"` +
  `models.providers.openai.compat.supportsPromptCacheKey: true`（+`supportsLongCacheRetention: true`）。
  大杠杆，但 DashScope 是否接受该参数需真跑确认；若首条请求报模型错即回滚此两项。
- **Lobster**（复杂工作流编排，省工具调用 token）：当前未安装，可 `openclaw` 生态安装后启用。
- **AGENTS.md 瘦身**（约 4.1K tokens/轮）：行为影响需实跑验证，谨慎。

---

## 5. 部署后验证
```powershell
.\tools\status.ps1                                   # 版本/网关/任务/模型/API
openclaw config validate                             # 配置 schema 合法
Get-ScheduledTask 'OpenClaw *' | ft TaskName,State   # 三任务 Ready
Test-NetConnection 127.0.0.1 -Port 18789             # 端口监听
```

## 6. 常见问题
| 现象 | 处理 |
|------|------|
| 开机不自启 | `OpenClaw Gateway` 任务别是 Disabled；重跑 `openclaw_silent_boot_guardian.ps1` |
| 大模型报错 | `status.ps1` 看 API 是否安全模式（key 空）；`set-api.ps1 -Show` |
| 启动慢/超时 | 确认 `update.checkOnStart=false`；本地代理是否就绪 |
| 想零花费 | `.\api.ps1 off` |

> 更细的运维/故障排查见 [MAINTENANCE.md](MAINTENANCE.md)；日常使用见 [USAGE.md](USAGE.md)。
