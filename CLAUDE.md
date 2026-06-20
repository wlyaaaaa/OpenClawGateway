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

## 3. 当前模型/端点状态（易变，不写死进公开文档）
- OpenClaw 主模型 = `qwen3.7-max-2026-05-20`（用户指定）；Cline 也用它/01-23。
- 端点 = 阿里云 MaaS（OpenAI 兼容），key 在 `~/.openclaw/config.yml` 与 `auth-profiles.json`。
- 已注册：0520 / 0517 / preview / `qwen3-max-2026-01-23`(降级)。**qwen-max 已删**。
- 🔴 **关键修复别回退**：`models.providers.openai.api = "openai-completions"`。此端点不认 `role="tool"`，用 responses 会让**工具/技能调用 400 失败**；completions（function 角色）才行。
- 思考 = `adaptive`（难题自动拉满，可 `/think max`）；`contextPruning ttl=30m`（只裁旧工具输出，不丢对话）。
- 缓存 `cacheRetention=long` 已设但此端点不返回 cached_tokens，无可测收益（无害）。
- 切端点/模型工具：`.\set-api.ps1`（注意 PowerShell ConvertTo-Json 会损坏 models 数组，**改 openclaw.json 用 Python**）。

## 4. 计划任务（schtasks）
`OpenClaw Gateway`(开机自启 S4U) · `OpenClaw Heartbeat`(15min,已暂停可启用) · `OpenClaw Update`(周日,已暂停) · `WeFlow Watchdog`(登录+15min) · `WeChat AutoStart`(登录) · `OpenClawGateway AutoPush`(每日3点归档推送)。

## 5. 联想 skills（提到就触发，均 Ready+Visible）
`cline-coding`(代码/多文件→委托Cline) · `wechat`(微信/群消息→WeFlow API) · `lobster`(复杂多步→确定性管道省token)。规则在 `workspace\TOOLS.md` + `~\Documents\Cline\Rules\`。

## 6. 踩过的坑（务必知道）
- **PowerShell 5.1 跑含中文的 .ps1 必须 UTF-8 BOM**，否则按 GBK 解析报错。新建 .ps1 后用 .NET `UTF8Encoding($true)` 转 BOM。
- **改 openclaw.json / cline providers.json 用 Python**（PowerShell ConvertTo-Json 会损坏结构、深度截断）。
- 模型 403 多半是**快速连发限流**，加 2s 间隔重测往往就 OK。
- `openclaw cron delete` 需设备 scope 审批；disable dreaming + 重启即可移除其 cron。
- 公开仓库推送前必扫机密（模式见 `tools/auto-archive-push.ps1`：TG token / DashScope key 前缀 / 网关密码 / 私钥头）。

## 7. 已知遗留 / 可继续
- TG token 仍在 RamdiskGuardian git 历史（建议 BotFather 轮换，未做）。
- ClineAgent 的 `使用说明openclow.pdf` 已删；workspace 有 `client_secret.json`(Google OAuth,本地)。
- 缺依赖技能（1password/discord/goplaces 等）需装 CLI 才可用。
- 详细历程见 `journal\` 各日期文件。
