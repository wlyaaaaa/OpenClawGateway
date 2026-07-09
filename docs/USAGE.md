# 日常使用指南

> 适配：OpenClaw v2026.6.10 + DashScope/Qwen。
> **默认即最强**：默认模型 `qwen3.7-plus`（手机+电脑统一）+ 思考等级 `max`（追求能力，不为省钱妥协）。
> 当前 API **已启用（ON）**，机器人可直接用；想零花费时 `api.ps1 off` 回安全模式（清空 key）。

## 0. 开始使用
```powershell
# 点亮机器人（还原 key、保持 Telegram/飞书 enabled、开 funnel、重启）
powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\enable-openclaw-api.ps1
```
然后手机 Telegram / 飞书给 bot 发消息即可。用完若想零花费：`disable-openclaw-api.ps1`，它不会把 Telegram / 飞书 `enabled` 改成 `false`。

## 1. 模型与思考（默认已拉满）
- 默认就是最强推理模型 + 最高思考；一般无需手动调。
- 临时换模型/降思考（省 token 或加速）用斜杠命令或脚本：
```powershell
.\tools\switch-model.ps1 -Model qwen3-max-2026-01-23 -Thinking medium   # 临时换轻量
.\tools\switch-model.ps1 -Model qwen3.7-plus -Thinking max     # 切回最强
```
- **新模型上线**（阿里出新版）时：`.\tools\switch-model.ps1 -Model <新id> -Register`。

## 2. 常用斜杠命令（聊天框直接发）
| 命令 | 作用 |
|------|------|
| `/new` | 重置会话。**长对话会 context overflow（历史崩溃根因），换任务就 /new** |
| `/model` ｜ `/model set <id>` | 查看 / 切换模型 |
| `/think off\|low\|medium\|high\|max` | 临时调思考深度 |
| `/reasoning on\|off` | 显示 / 隐藏思考过程 |
| `/settings` ｜ `/doctor` | 配置看板 / 自检 |

## 3. 手机 ChatOps（核心玩法）
手机 Telegram 给 bot 下任务，它在 Win11 后台执行，结果回传聊天框。
例：“用本地 cline 打开 bilibili 截图保存到 E:\ClineAgent\test.png，完成后把图发我”。
OpenClaw 收到 → 调本机 Cline CLI → 截图 → 回传。

## 4. 渠道与安全
- 当前 **Telegram** 和 **飞书** 的 `enabled` 长期开关保持开启；API key 脚本不得改写它们。
- Telegram 白名单仅你的 ID（`8320970051`，已去 `"*"`）；飞书也必须使用正确白名单（飞书用 open_id，别用 `"*"`）。
- Google Chat 默认关；要用先填正确白名单再启用。
- `commands.bash` 开着＝聊天可在本机执行命令，务必只对可信白名单开放。

## 5. 成本与稳定（信息参考，不强制）
- 你优先“最强”，默认已最强；如某段时间想省，临时用 `qwen3-max-2026-01-23` + `/think low`。
- `memory-core.dreaming` 默认**关**（开=后台自动思考会持续花费）。
- 长期不用就 `disable`（安全模式，零花费）。
- Node 堆已设 1536MB，重载多渠道时更不易 OOM。

## 6. 一屏自检
```powershell
.\tools\status.ps1     # 版本/网关/任务/模型/思考/API模式/渠道/Funnel
```


## 7. 在 Telegram/飞书 对话式控制（owner 直接发）
| 发什么 | 作用 |
|--------|------|
| `/model` ｜ `/model set <id>` | 看 / 切模型 |
| `/think off..max` | 调思考等级 |
| `/new` | 开新会话 |
| `/status` ｜ `/settings` ｜ `/doctor` | 网关状态 / 配置看板 / 自检 |
| "汇报系统/脚本状态" | 它会跑 `tools/status.ps1` 简洁汇报（版本/网关/任务/模型/思考/渠道） |

## 8. ⚠️ 自动更新：不要点应用内的"自动更新"按钮
- **应用内/原生 `openclaw update`** 会跑 **doctor + schema 迁移**，可能：补回 `*` 白名单、**把 `api` 改回 `responses`→ 技能全部 400 失败**、覆盖自定义开机任务。**风险高，别按。**
- **要更新就跑** `powershell -File E:\Projects\Tools\OpenClawGateway\openclaw_update.ps1`（**只用 npm，不跑 doctor**，且更新后**自动重断言 `api=openai-completions`** 自愈）。
- 万一手滑点了应用内更新：**事后跑一次 `openclaw_update.ps1`** 即可自愈关键配置。
- 永远别跑 `openclaw doctor --fix`（它会补回 `*`）。
- 更新前先 `tools/backup-config.ps1` 备份，坏了能回滚。

## 9. 在 codeg 控制台里用 OpenClaw（详见 [CODEG.md](CODEG.md)）
- ❌ **别用** codeg 的「OpenClaw」ACP agent —— per-session MCP + auth 握手是 codeg 的 bug，走不通。
- ✅ 用 **Cline** agent + 挂 `openclaw-bridge` MCP（**必须带网关密码** `OPENCLAW_GATEWAY_PASSWORD`）。
- 一键配置：`powershell -ExecutionPolicy Bypass -File E:\Projects\Tools\OpenClawGateway\tools\setup-codeg-bridge.ps1` → codeg「MCP」页点刷新 → 把 openclaw-bridge 勾给 Cline → 用 Cline 发任务。
- 配好后 Cline 可调 OpenClaw 的 9 个对话工具（列对话 / 读发消息 / 轮询事件 / 处理审批）。
