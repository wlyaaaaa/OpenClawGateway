# 2026-06-21 — codeg 接入定案 + 文档全面收口

> 本轮重点：彻底查清 codeg↔OpenClaw 的接法、把"思考"调回 max、修文档漂移、新增 codeg 文档与一键脚本、重生成 PDF 并推送。

## A. codeg ↔ OpenClaw：定案（详见 docs/CODEG.md）
- **ACP 直连（codeg 的 OpenClaw agent）= 死路**：codeg 的 ACP 客户端 ① authenticate 握手不完整；② 始终发送 per-session `mcpServers` 字段（删光本地 MCP 仍发空字段），OpenClaw ACP 桥一律拒绝。`openclaw acp` 无任何相关开关。两端都改不了 → codeg 侧 bug。
- **可行路径 = Cline + openclaw-bridge MCP**：codeg 用 Cline（PASS）当 agent，挂 `openclaw mcp serve` 暴露的 MCP。
- **关键坑：必须带网关密码**。`gateway.auth.mode=password`，openclaw-bridge 不带 `OPENCLAW_GATEWAY_PASSWORD` 即报 `Authentication required: Call authenticate before creating a session`。
- **实测**：带密码后 `initialize`+`tools/list` 返回 9 个工具（conversations_list / conversation_get / messages_read / messages_send / events_poll / events_wait / attachments_fetch / permissions_list_open / permissions_respond）。即 codeg 的 Cline 可读写 OpenClaw 的对话/消息/审批。
- **新增一键脚本** `tools/setup-codeg-bridge.ps1`：从机器级环境变量取密码 → 写入 Cline 生效配置（codeg 检测此文件）→ 探活 18789 → 打印收尾步骤。已实跑通过（PARSE OK + [OK] 网关在线）。
- 用户当时选择"暂时不用了"，但本轮把**完整解法固化进脚本+文档**，随时可一键接上。

## B. 配置调优
- **思考等级 `adaptive` → `max`**：honor 用户多次强调的"最高思考、AI 不能太蠢、成本次要"。adaptive 有概率把难题误判为简单而欠思考，max 杜绝此风险。`config validate` 通过。临时降挡仍可用 `tools/set-thinking.ps1`。
- `.gitignore` 增补：排除 `*.zip / codeg-backup-* / *.bak / secrets-backup-*`（防 28MB 的 codeg 备份等误入公开仓库）。

## C. 文档漂移修正（十几轮未更，本轮校准）
- 默认模型：文档多处写 `qwen3.7-max-2026-06-08` / 泛指 `qwen3.7-max` → 全部校正为实际默认 **`qwen3.7-max-2026-05-17`**。
- 已删模型 `qwen-max` 仍出现在 switch-model 示例 → 改为 `qwen3-max-2026-01-23`（轻量层）。
- API 状态：README/USAGE 写"安全模式" → 实际 **API ON（key 在）**，已改为"已启用，闲时 off 回零花费"。
- 计划任务态：README/CLAUDE 写"Heartbeat 暂停" → 实际 **Ready**；`OpenClaw Update` = **Disabled（故意）**。已校正。
- 更新文件：`README.md`、`CLAUDE.md`、`docs/USAGE.md`、`docs/MAINTENANCE.md`；新增 `docs/CODEG.md`。

## D. 体检快照（本轮实测）
- 版本 2026.6.8 · 网关 18789 在线 · `config valid` · `api=openai-completions`（命门保持）· thinking=max · 默认模型 0517 · telegram+feishu enabled。
- 任务：Gateway/Heartbeat/AutoPush/WeFlow Watchdog = Ready；OpenClaw Update = Disabled（故意）。

## E. 产出
- 新文件：`docs/CODEG.md`、`tools/setup-codeg-bridge.ps1`、本日志。
- 改文件：`README.md`、`CLAUDE.md`、`docs/USAGE.md`、`docs/MAINTENANCE.md`、`.gitignore`。
- 重新生成 docs/*.pdf 并推送 GitHub。
