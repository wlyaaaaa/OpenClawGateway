# 2026-06-21 — 省 token 框架 + 技能审计 + 不降智调参

## 核心框架:三类 token,只砍第二类
| 类型 | 内容 | 动它降智? | 处置 |
|------|------|:---:|------|
| ① 智能必需 | 身份/核心规则、**当前任务**历史、MEMORY.md、max 思考 | 会 | 绝不动 |
| ② 纯浪费 | 没用的技能/插件、模板废话、**跨任务的旧历史** | 不会 | 免费砍 |
| ③ 取舍 | 压缩阈值、in-task 历史深度 | 过激会 | 温和上限 |

关键洞察：「100-200K 请求」主因是历史累积，但历史分两种——**当前任务历史是①（砍=降智），上个任务遗留是②（纯浪费）**。区分二者＝"不降智省 token"的钥匙。

## 本轮动作
### A. 技能审计（②，最大免费杠杆）
- 真相：共 **82 技能、44 对模型可见**（每轮加载描述）。一整套编码"超能力"（TDD/系统调试/code-review/git-worktrees/写计划…）+ 调试器（node/python-debugpy/agent-browser）+ 没用集成（notion/obsidian/飞书文档×4/meme/canvas/diagram/gemini/gh-issues）+ 语音（whisper/sherpa-tts）+ 杂项（discord/1password/goplaces/oracle/nano-pdf/session-logs）——OpenClaw 委托 Cline 编码，全不用。
- **机制**：`skills.entries.<slug>.enabled=false`（无 CLI disable，靠配置）。
- **结果：可见技能 44 → 10**，禁用 71。保留：cline-coding/wechat/himalaya/lobster/github/gog/weather/taskflow/healthcheck（+self-improving/summarize 备用）。零降智（砍的都没在用）。

### B. 不降智调参（③）
- 上一轮 `contextTokens=64000` 偏激进（复杂任务中途压缩=降智）→ **回调 80000**：压住失控（≤80K）又给复杂任务留头寸。

### C. 梦境处置（决策：保留）
- 梦境=**反降智发动机**：蒸馏日志进 MEMORY.md + 降幻觉，是"/new 不降智"的前提。**留用 + 便宜模型 qwen3-max-2026-01-23 + 一夜一次**。每次 ~19K，稳赚。

### D. 最关键的非技术杠杆
**换任务就 `/new`**：旧任务历史对新任务是纯②浪费，丢掉零降智（MEMORY.md 靠梦境保住该记的）。比调任何参数都省。

## 现状
可见技能 10 · contextTokens 80000 · dreaming 便宜模型 · googlechat off · 指令文件 -44% · 配置已推私有云 openclaw-backup · 网关在线 config valid。
