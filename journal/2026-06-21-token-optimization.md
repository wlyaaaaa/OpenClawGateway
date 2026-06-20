# 2026-06-21 — 工作区瘦身 + 请求 token 优化 + OpenClaw 私有云备份

## A. 工作区指令文件瘦身（每轮加载，省 token）+ 身份注入
- 每轮加载的 5 文件 **21952→12154 字节，省 44%**（AGENTS.md 12461→4857，−61%）。
- 注入伴侣身份：IDENTITY.md（空模板→"有记忆的 AI 伴侣"+三特点：有记忆/会主动/能操作电脑）、SOUL.md 强化伴侣定位、TOOLS.md 加帮手名册（含 **Claude Code 也能操作电脑**）。
- 删各文件底部 `## Related`/模板废话；统一 cline 用法 `cline -c "<repo>" "<task>"`；修 TOOLS.md 的 `\t` 被当制表符 bug（改正斜杠）。
- 原文件备份在 `C:\Users\10979\.openclaw\workspace-backup-20260621-051855\`。

## B. 请求 token 大头定位与优化（真相）
- 查 `agents/main/sessions/sessions.json` 的 `systemPromptReport`：固定系统提示 = projectContext ~17K 字符 + nonProjectContext ~29K 字符 ≈ 15-18K token/轮。
- **100-200K 的真凶＝会话历史累积**：实测 feishu 一次请求 inputTokens=127675；会话涨到 96-128K 才触发压缩（compaction tokensBefore=115748→after=14418）。`contextTokenBudget=96000` 太高。
- **优化**：
  1. `contextTokens` 全模型 **96000→64000**：更早压缩，worst-case 请求 ~128K→~64K（约腰斩）。
  2. `dreaming.model` = **qwen3-max-2026-01-23**（后台记忆巩固不需最强模型；dreaming 实测 ~19K/run）。
  3. 关 **googlechat 插件**（用 TG+飞书，没用 Google Chat，白塞工具定义）。
  4. 指令文件瘦身（见 A）降 projectContext。
- 缓存：MaaS 端点不返回 cached_tokens，前缀缓存省不了（用户已知，无解）。
- 已重启网关，`contextTokens=64000` 生效，config valid。
- 取舍：64000 仍留 ~44K 可用上下文，正常聊天够；长会话会更早压缩（更省但记得略少），可 `/new` 规避或调回。

## C. OpenClaw 私有云备份（恢复用）
- 新建**私有**仓库 `wlyaaaaa/openclaw-backup`（核实 visibility=PRIVATE）。
- 内容：`config/`（openclaw.json/auth-profiles.json/config.yml/.env，**含密钥**）+ `workspace/`（人格/记忆/技能/脚本，排除 node_modules）。380K。
- 脚本 `tools/backup-openclaw.ps1`（CRLF 防坑同 claude-memory）；加入计划任务 `OpenClaw Memory Backup`（现 2 动作：记忆+OpenClaw，04:00+13:00）。
- 三仓恢复体系：公开 `OpenClawGateway`（脚本/文档）+ 私有 `claude-memory`（Claude 记忆）+ 私有 `openclaw-backup`（OpenClaw 配置+工作区）。

## 全局
网关在线 · config valid · 默认模型 0517 · thinking max · contextTokens 64000 · dreaming 便宜模型 · googlechat off · 三仓备份(每日 04:00+13:00)。
