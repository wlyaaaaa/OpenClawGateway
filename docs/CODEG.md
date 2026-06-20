# codeg ↔ OpenClaw / Cline 接入指南

> 适配：codeg 控制台（`C:\Users\10979\AppData\Local\codeg`）+ OpenClaw v2026.6.8 + Cline CLI。
> 本文记录把 codeg 接到 OpenClaw 的**唯一可行路径**、踩过的坑与一键脚本。
> 公开仓库：文中 `<网关密码>` 等为占位符，真实凭据只在本机。

---

## 0. 一句话结论

> **codeg 里别用「OpenClaw」这个 ACP agent（走不通，是 codeg 侧 bug）。
> 改用「Cline」当 agent + 给它挂 `openclaw-bridge` MCP（带网关密码）来调用 OpenClaw。**

一键配置：
```powershell
powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\tools\setup-codeg-bridge.ps1
```

---

## 1. codeg 里「用 OpenClaw」的两条路

codeg 的「智能体 / Agent SDK 管理」把 OpenClaw、Cline、Claude Code 等都列为可连接的 **ACP agent**；
「MCP」页则可把 MCP 服务挂给某个 agent。于是有两种思路：

| 方式 | 在 codeg 哪里 | 协议 | 结论 |
|------|--------------|------|------|
| ❌ 把 OpenClaw 当 **agent** | 智能体 → 选「OpenClaw」 | ACP | **死路**：codeg 的 ACP 客户端 ① authenticate 握手不完整 ② 始终发送 per-session `mcpServers` 字段，而 OpenClaw 的 ACP 桥拒绝 per-session MCP。两端都没有开关，属 codeg 侧 bug。 |
| ✅ 把 OpenClaw 当 **工具（MCP）** | MCP → `openclaw-bridge` 勾给 Cline | MCP | **可行**：Cline（一个能正常工作的 agent）通过 `openclaw mcp serve` 暴露的 MCP 工具去读写 OpenClaw 的对话/消息。 |

### 1.1 为什么 ACP 直连是死的（已穷尽排查）

- 报错 A（用 OpenClaw agent 时）：
  `ACP protocol error: Internal error: { "details": "ACP bridge mode does not support per-session MCP servers. Configure MCP on the OpenClaw gateway or agent instead." }`
  → codeg 在 `session/new` 里始终带 `mcpServers` 字段（**即使你把 codeg 里的 MCP 全删光，仍发空字段**），OpenClaw 的 ACP 桥一律拒绝。
- 报错 B（认证阶段）：
  `ACP protocol error: Authentication required: Call authenticate before creating a session`
  → ACP 客户端要先 `authenticate` 再 `session/new`，codeg 的握手没走完整。
- `openclaw acp --help` **无任何**「允许 / 忽略客户端 MCP」的参数；`acp` 配置段只有 `enabled / dispatch / backend / fallbacks`。
- 结论：**OpenClaw 侧无法配置接受**，codeg 侧又**无开关关闭** per-session MCP → 只能等 codeg 更新或反馈作者。

---

## 2. 可行路径：openclaw-bridge MCP（带网关密码）

### 2.1 关键：必须带网关密码

OpenClaw 网关 `gateway.auth.mode = "password"`。`openclaw mcp serve` 连网关时若不带密码，
Cline 一调用工具就报：
`Authentication required: Call authenticate before creating a session`（与 ACP 报错 B 同文案，但这次是 MCP 侧）。

补上密码即解决。密码来源 = 机器级环境变量 `OPENCLAW_GATEWAY_PASSWORD`。

### 2.2 MCP 配置（codeg「MCP」页 → openclaw-bridge → 配置 JSON）

```json
{
  "type": "stdio",
  "command": "C:\\Users\\10979\\AppData\\Roaming\\npm\\openclaw.cmd",
  "args": ["mcp", "serve"],
  "env": {
    "OPENCLAW_URL": "http://127.0.0.1:18789",
    "OPENCLAW_GATEWAY_PASSWORD": "<网关密码>"
  }
}
```

> codeg 会检测 Cline 的生效配置 `C:\Users\10979\.cline\data\settings\cline_mcp_settings.json`；
> `setup-codeg-bridge.ps1` 会把上面的配置（密码自动从环境变量取）写进该文件，省去手填。

### 2.3 实测：带密码即认证成功，暴露 9 个工具

用 MCP `initialize` + `tools/list` 驱动，返回：

| 工具 | 作用 |
|------|------|
| `conversations_list` | 列出 OpenClaw 对话（Telegram / 飞书 等渠道） |
| `conversation_get` | 按 session key 取某个对话 |
| `messages_read` | 读某对话最近消息 |
| `messages_send` | 通过同一路由回发消息 |
| `events_poll` / `events_wait` | 轮询 / 等待对话事件 |
| `attachments_fetch` | 取某消息的非文本附件 |
| `permissions_list_open` | 列出待审批的 exec / plugin 请求 |
| `permissions_respond` | allow/deny 某个待审批请求 |

> 即：**codeg 里的 Cline 能读写 OpenClaw 的对话、收发消息、处理审批**——这就是「codeg 用上 OpenClaw」的实际形态。
> （注意：这是桥接 OpenClaw 的**消息 / 渠道**能力，不是「把 OpenClaw 当编码大脑驱动」——后者是 ACP 死路。）

---

## 3. 完整接入步骤

1. **配 MCP**（二选一）：
   - 一键：`powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\tools\setup-codeg-bridge.ps1`
   - 手动：codeg → 设置 → MCP → 编辑 `openclaw-bridge` 的配置 JSON（见 2.2），点「保存」。
2. **刷新**：codeg → MCP → 点「刷新」，确认出现 `openclaw-bridge`。
3. **挂给 Cline**：在 `openclaw-bridge` 的「启用应用」里**勾选 Cline**（不要勾 OpenClaw）。
4. **配 Cline 模型凭据**（智能体 → Cline）：
   - Provider = `OpenAI Compatible`
   - API URL = `https://ws-50ggmajfpk06feuv.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`
   - API Key = `<DashScope/MaaS key（sk-ws-…）>`
   - Model = `qwen3.7-max-2026-05-17`（⚠️ 别用默认占位的 `claude-sonnet-4-5`，该端点没有此模型）
   - 也可在「环境变量」里注入 `OPENAI_BASE_URL` / `OPENAI_API_KEY`（与上面一致）。
5. **用 Cline 这个 agent 发任务**（切勿用 OpenClaw ACP agent）。

---

## 4. codeg 各 agent 状态（参考）

| Agent | 预检 | 能用 | 备注 |
|-------|------|------|------|
| Claude Code | PASS | ✅ | |
| Gemini CLI | PASS | ✅ | |
| **Cline** | PASS | ✅ | **本方案主角**：挂 openclaw-bridge 调 OpenClaw |
| OpenClaw | 版本 PASS | ❌(ACP) | per-session MCP + auth 死结，别用 |
| Codex CLI / OpenCode / Hermes | FAIL | — | 未安装 / 未配置 |

---

## 5. 故障排查

| 现象 | 原因 | 处理 |
|------|------|------|
| `Authentication required: Call authenticate before creating a session`（Cline 下） | openclaw-bridge 没带网关密码 | 在 MCP env 加 `OPENCLAW_GATEWAY_PASSWORD`（或跑 setup 脚本） |
| `ACP bridge mode does not support per-session MCP servers`（OpenClaw 下） | 用了 OpenClaw ACP agent，codeg 必发 per-session MCP | **改用 Cline**，放弃 OpenClaw agent |
| Cline 报模型不存在 / 4xx | Model 填成 `claude-sonnet-4-5` 但端点是 Qwen | Model 改 `qwen3.7-max-2026-05-17` |
| MCP「未检测到本地 MCP」 | Cline 生效配置为空 | 跑 setup 脚本写回，再点「刷新」 |
| 网关 18789 未响应 | Gateway 计划任务没起 | `Start-ScheduledTask 'OpenClaw Gateway'` |

---

## 6. 一键脚本说明

`tools/setup-codeg-bridge.ps1`：
1. 从机器级环境变量读 `OPENCLAW_GATEWAY_PASSWORD`；
2. 把带密码的 `openclaw-bridge` 写进 Cline 生效配置（codeg 检测此文件）；
3. 探活网关 18789；
4. 打印 codeg 内收尾步骤。

> 重装 / 复现时一条命令即可恢复 codeg↔OpenClaw 接入，无需手填密码。

---

## 7. 等 codeg 修复后

ACP 直连若想用，需 codeg 侧修两点：① 补全 `authenticate` 握手；② 连 OpenClaw 时不发 per-session `mcpServers`（或提供关闭开关）。
可向 codeg 作者反馈本文 §1.1 的两条报错。在此之前，**Cline + openclaw-bridge 是唯一稳定接法**。
