# 最终状态与决策文档（2026-06-20）

> 给用户和新 AI 会话看的完整快照。模型/端点易变，细节不写死进公开仓库正文。

## A. 你的资源包能不能给 OpenClaw 用？（实测结论）
| 资源包 | 能用？ | 关键限制 / 用法 |
|--------|--------|----------------|
| **LLM 包**（qwen-plus / qwen-max / qwen-turbo） | ✅ **能**（dashscope 上三个模型实测全通） | **只抵扣"非思考模式"实时推理**；**不抵扣上下文缓存、Batch、调优、部署**。若要省钱可把 `qwen-plus`(最便宜、非思考)当廉价层 |
| **图像包**（qwen-image / qwen-image-plus） | ⚠️ **能但要接原生 API** | OpenAI-compat 的 images 端点 404；需走 DashScope **原生文生图 API**(`/services/aigc/text2image`)才抵扣 |

**你的选择**：不切资源包模型，统一用 **qwen3.7-max-2026-05-20**（你会在阿里云开通其自动支持）。合理——保住"最高思考"。资源包作为**备选省钱方案**留档（想省时把简单任务/Cline 切到 qwen-plus 即可，≈免费）。

## B. 自动更新会不会失效配置？（深度分析 + 已加自愈）
- **现状**：`OpenClaw Update` 任务 Disabled + `update.auto=false` → 现在不会自动更新，零风险。
- **风险**：原生 `openclaw update`(含 doctor)会补回 `*` 白名单、可能重写 gateway.cmd；新版本 schema 迁移**可能把 `api` 改回 `responses` → 技能全 400 失败**。
- **已加自愈**：`openclaw_update.ps1` 更新后**自动重断言 `api=openai-completions`**、检查 `*` 白名单、校验 config——新版本改坏也能自愈。**永不跑 `doctor --fix`**。
- 建议更新前先 `backup-config.ps1`。

## C. 本轮已改的设置
| 项 | 状态 |
|----|------|
| OpenClaw + Cline 模型 | 统一 **qwen3.7-max-2026-05-20**（Cline 也在 MaaS 端点） |
| `api=openai-completions` | ✅ 保持（修复技能 400 的命门） |
| `OpenClaw Heartbeat` | ✅ 重新启用（挂死自愈） |
| dreaming | ✅ 开（你的选择；NO_REPLY 是正常的后台记忆任务，非故障） |
| plugins.allow | ✅ 8 可信插件白名单 |
| 模型 fallback 链 | ⚠️ 尝试失败(schema 格式待查)，已回退，不影响主用 |

## D. 必要功能 + 对应技能/插件（已就绪 ✅ / 需补 ⏳）
- **语音**：STT `openai-whisper-api` ✅；TTS `sherpa-onnx-tts` ⏳(已启用，需下载 sherpa 运行时+语音模型)
- **主动提醒/待办**：`commitments`/`cron`/`taskflow` ✅
- **日程/邮件/笔记**：`gog`(Gmail/日历) ✅、`himalaya`(邮件) ✅、`notion` ✅
- **浏览器/研究**：`agent-browser`/`browser-automation` ✅、`web_search` ✅
- **图像**：内置 image 工具 + 百炼 t2i/i2i（图像包需接原生 API）
- **记忆**：`memory-wiki` + 梦境 ✅
- **复杂编排省 token**：`lobster` ✅
- **联想路由**：`cline-coding`/`wechat`/`lobster` ✅ Ready+Visible（live 验证过）

## E. 当前系统全绿
主模型 0520 · api=completions · adaptive 思考 · 30m pruning · 工具/技能/记忆/多模态/微信路由 live 正常 · Heartbeat 自愈开 · plugins 白名单 · 更新脚本带自愈。
