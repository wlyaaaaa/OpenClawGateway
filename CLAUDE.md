# CLAUDE.md — 新会话交接文档（OpenClaw 个人智能体网关运维体系）

> 这是给**新 Claude Code 会话**的上下文交接。把工作目录设为 `E:\OpenClawGateway` 即自动加载本文件。
> 用户：简体中文沟通；本机有 root/管理员；关注 LLM 费用与稳定性。

## 0. 用户的工作流偏好（重要）
- 复杂任务：**先给计划+预执行任务清单 → （除非用户明说"免审批/你有root/自行决策"，否则征求意见）→ 执行 → 给报告+完成任务清单**。
- **归档在一处**：把计划/报告写到 `E:\OpenClawGateway\journal\<日期>.md`；由计划任务 `OpenClawGateway AutoPush` 每日自动推 GitHub（带机密扫描守卫）。
- **不写长期记忆**（除非用户要求）。不要把上一轮任务继续往下一轮硬塞。
- 用户给"无须审批立刻执行/root/自行决策"时 → 直接干，不要反复提问。

## 1. 这套体系是什么
本机 **OpenClaw v2026.6.8**（个人智能体网关，昵称"小龙虾"）+ 三个协作件：
- **OpenClaw**：主脑网关。配置在 `C:\Users\10979\.openclaw\`（`openclaw.json` 配置、`workspace\` 指令+skills、`auth-profiles.json` 密钥）。loopback:18789。
- **Cline**（`C:\Users\10979\.cline\`，CLI 全局装）：OpenClaw 的**廉价编码手**。真实配置在 `data\settings\providers.json → providers.openai-compatible.settings`（不是 globalState！）。
- **WeFlow**（`C:\Program Files\WeFlow\WeFlow.exe`，API 在 `127.0.0.1:5031`）：读微信消息。bridge 在 `E:\WeFlowBridge`（公开仓库），token 在其 `.env`。

## 2. 仓库（都在用户 GitHub `wlyaaaaa`）
| 本地 | GitHub | 说明 |
|------|--------|------|
| `E:\OpenClawGateway` | OpenClawGateway (public) | **本体**：运维脚本/文档/bootstrap/journal/auto-push |
| `E:\WeFlowBridge` | WeFlowBridge (public, **master 分支**) | 微信 API bridge + 看门狗 |
| `E:\ClineAgent` | 无 remote（本地） | Cline 工作沙箱，含 .clinerules |
| `E:\RamdiskGuardian` | RamdiskGuardian (public) | 独立 RAM 盘项目（已清空 openclaw） |
| `E:\TimeAudit` | TimeAudit (public) | 有 `build_docs_pdf.py`（md→PDF，白绿主题） |
| `E:\ClaudeMemoryBackup` | claude-memory (**private**) | Claude 记忆云备份（已脱敏）；新机拷 `*.md` 回 `.claude\...\memory\` 即恢复 |
| `E:\OpenClawBackup` | openclaw-backup (**private**) | OpenClaw config+workspace 云备份（含密钥/人格/记忆，恢复用） |

## 3. 当前模型/端点状态（易变，不写死进公开文档）
- OpenClaw 主模型 = `qwen3.7-max-2026-05-17`（**手机+电脑默认**，用户指定）；Cline 也用同端点此模型。
- 端点 = 阿里云 MaaS（OpenAI 兼容）`https://ws-50ggmajfpk06feuv.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`，key 在 `~/.openclaw/config.yml` 与 `auth-profiles.json`。
- 已注册：0520 / 0517 / preview / `qwen3-max-2026-01-23`(降级)。**qwen-max 已删**。0520 免费额度曾耗尽（用户在阿里云补额度）。
- 🔴 **关键修复别回退**：`models.providers.openai.api = "openai-completions"`。此端点不认 `role="tool"`，用 responses 会让**工具/技能调用 400 失败**；completions（function 角色）才行。
- 思考 = `max`（用户要"最高思考、AI 不能太蠢"，成本次要；`adaptive` 有概率把难题误判为简单而欠思考，已弃用）；`contextPruning ttl=30m`（只裁旧工具输出，不丢对话）。临时降挡用 `tools\set-thinking.ps1`。
- **省 token 调优（2026-06-21）**：`contextTokens` 全模型 **96000→64000**（更早压缩，单次请求 worst-case ~128K→~64K；历史累积是请求 token 大头，非 dreaming）；`dreaming.model=qwen3-max-2026-01-23`（后台巩固用便宜模型）；关 `googlechat` 插件（省工具定义）；workspace 指令文件已瘦身 44%。MaaS 端点不返回 cached_tokens，前缀缓存无效（无解）。
- 缓存 `cacheRetention=long` 已设但此端点不返回 cached_tokens，无可测收益（无害）。
- 切端点/模型工具：`.\set-api.ps1`（注意 PowerShell ConvertTo-Json 会损坏 models 数组，**改 openclaw.json 用 Python**）。

## 4. 计划任务（schtasks）
`OpenClaw Gateway`(开机自启 S4U,**Ready**) · `OpenClaw Heartbeat`(15min,**Ready**) · `OpenClaw Update`(周更,**Disabled**=故意,改用 `openclaw_update.ps1` 手动/自愈) · `WeFlow Watchdog`(登录+15min,Ready) · `WeChat AutoStart`(登录) · `OpenClawGateway AutoPush`(每日归档推送,Ready) · `OpenClaw Memory Backup`(**每日 04:00+13:00**,Ready,跑 `tools\backup-memory.ps1`：本地 `memory-backup\` 轮换 + 推私有云仓库 `wlyaaaaa/claude-memory`)。
> ⚠️ **更新只走命令行**：`openclaw_update.ps1`（npm-only+自愈）；**绝不点应用内/原生 `openclaw update`**（跑 doctor 会改坏 api/白名单/gateway.cmd）。

## 5. 联想 skills（提到就触发，均 Ready+Visible）
`cline-coding`(代码/多文件→委托Cline) · `wechat`(微信/群消息→WeFlow API) · `lobster`(复杂多步→确定性管道省token)。规则在 `workspace\TOOLS.md` + `~\Documents\Cline\Rules\`。

## 5b. codeg 控制台接 OpenClaw（详见 `docs/CODEG.md`）
- codeg 的「OpenClaw」**ACP agent 走不通**（per-session MCP + auth 握手 codeg bug，两端无开关）。
- 唯一可行：codeg 用 **Cline** agent + 挂 `openclaw-bridge` MCP（**必须带 `OPENCLAW_GATEWAY_PASSWORD`**，否则报 "Authentication required"）。实测暴露 9 个对话工具。
- 一键配置：`tools\setup-codeg-bridge.ps1`。

## 6. 踩过的坑（务必知道）
- **PowerShell 5.1 跑含中文的 .ps1 必须 UTF-8 BOM**，否则按 GBK 解析报错。新建 .ps1 后用 .NET `UTF8Encoding($true)` 转 BOM。
- **智能体自重启死锁**：不能直接运行 `openclaw gateway restart`，会因 schtasks /End 强杀父进程导致后续命令无法执行。必须运行 `powershell -File E:\OpenClawGateway\tools\restart_gateway.ps1`，其通过 WMI 机制（`Invoke-WmiMethod`）脱离进程树在后台安全重启。
- **改 openclaw.json / cline providers.json 用 Python**（PowerShell ConvertTo-Json 会损坏结构、深度截断）。
- 模型 403 多半是**快速连发限流**，加 2s 间隔重测往往就 OK。
- `openclaw cron delete` 需设备 scope 审批；disable dreaming + 重启即可移除其 cron。
- 公开仓库推送前必扫机密（模式见 `tools/auto-archive-push.ps1`：TG token / DashScope key 前缀 / 网关密码 / 私钥头）。

## 7. 已知遗留 / 可继续
- TG token 仍在 RamdiskGuardian git 历史（建议 BotFather 轮换，未做）。
- ClineAgent 的 `使用说明openclow.pdf` 已删；workspace 有 `client_secret.json`(Google OAuth,本地)。
- 缺依赖技能（1password/discord/goplaces 等）需装 CLI 才可用。
- 详细历程见 `journal\` 各日期文件。
