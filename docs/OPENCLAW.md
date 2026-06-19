# OpenClaw 个人智能体网关 — 运维手册（脱敏版）

> 本仓库只收录**运维脚本与文档**。所有密钥/令牌一律不入库，实际凭据保存在本机
> `C:\Users\10979\.openclaw\` 下（已 gitignore，永不提交）。文中出现的 `<...>`
> 均为占位符。

| 项目 | 值 |
|------|----|
| OpenClaw 版本 | v2026.6.8（npm 全局安装，stable 通道周更） |
| 网关端口 | 18789（仅 loopback 绑定） |
| 公网入口 | Tailscale Funnel（按需开启） → `http://127.0.0.1:18789` |
| LLM 供应端 | 阿里云百炼 DashScope（OpenAI 兼容端点），模型 `qwen3.7-max` / `qwen-max` |
| 配置文件 | `C:\Users\10979\.openclaw\openclaw.json` |
| 密钥库 | `C:\Users\10979\.openclaw\auth-profiles.json`（含 `agents\main\agent\` 副本） |
| 启动脚本 | `C:\Users\10979\.openclaw\gateway.cmd`（原生 daemon 生成） |

---

## 1. 架构总览

```
互联网 ──HTTPS──> Tailscale Funnel ──proxy──> 127.0.0.1:18789
                                                  │
                                          OpenClaw Gateway (Node.js)
                                          ├─ Control UI / Auth(password)
                                          ├─ Agent Engine (DashScope/Qwen)
                                          └─ Channel Router
                                             ├─ Telegram Bot
                                             ├─ Feishu(飞书)
                                             └─ Google Chat
```

OpenClaw（昵称“小龙虾”）是常驻后台的个人智能体网关，统一接收 Telegram / 飞书 /
Google Chat 消息，驱动 Qwen 大模型完成任务，并可调用本机 Cline CLI 等工具。

### 1.1 委托 Cline 省 token（主脑 + 廉价手）
对于多文件编码、脚本调试、浏览器自动化这类重活，OpenClaw 主脑（贵的 `qwen3.7-max`）
**不自己逐行读写**，而是经 bash 委托本地 **Cline CLI**（便宜的 `qwen-max` + diffs-only）：
```bash
cline -c "<目标仓库>" -m qwen-max "<一句话任务>"
```
主脑只下达任务、读回摘要、向用户汇报，**不把整个代码库读进上下文** —— 这是省 token 的关键。
委托规则写在工作区 `TOOLS.md`，Cline 全局规范在 `~/Documents/Cline/Rules/`。

## 2. 开机自启机制（两条路线，二选一）

### 2.1 原生方式（推荐，v2026.6.6 内建）
OpenClaw 2026.6.6 自带服务管理，底层在 Windows 上用计划任务（schtasks）：
```powershell
openclaw daemon install     # 安装/注册 "OpenClaw Gateway" 计划任务
openclaw daemon status      # 查看安装状态 + 连通性探测
openclaw daemon start|stop|restart
openclaw daemon uninstall
```
`openclaw update` 升级后会自动经此机制重启网关。

### 2.2 自定义静默守护（本仓库 `openclaw_silent_boot_guardian.ps1`）
在原生任务基础上，把 `OpenClaw Gateway` 任务重注册为**完全静默、开机即起**：

| 维度 | 设置 | 作用 |
|------|------|------|
| 触发器 | `BootTrigger +30s` | 系统引导即启动，**不依赖用户登录** |
| 身份 | `S4U` LogonType | 免密、无交互桌面、后台运行 |
| 权限 | `Highest` | 端口绑定 / Tailscale 等特权操作 |
| 窗口 | `wscript.exe → openclaw_run_hidden.vbs`（windowStyle=0） | 零黑窗闪烁 |
| 容错 | `RestartOnFailure 3×60s` + `StartWhenAvailable` | 失败自动重启、错过补跑 |

> ⚠️ 两条路线都管理**同名任务** `OpenClaw Gateway`。若以后运行 `openclaw daemon install`
> 或 `doctor --fix`，可能覆盖自定义注册（丢失 VBS 包装）。长期建议统一到 2.1 原生方式，
> 自定义脚本仅作灾备。

重新注册（管理员 PowerShell）：
```powershell
powershell -ExecutionPolicy Bypass -File "E:\OpenClawGateway\openclaw_silent_boot_guardian.ps1"
```

## 3. 心跳看门狗（`openclaw_heartbeat.ps1`）
计划任务 `OpenClaw Heartbeat` 每 15 分钟探测 `127.0.0.1:18789`；无响应则
`Stop`/`Start` 网关任务自愈。日志：`E:\OpenClawGateway\logs\openclaw_heartbeat.log`。
（v2026.6.6 已内建进程级 supervisor，此心跳作为外部兜底。）

## 4. 认证与免登录运行
- `gateway.auth.mode = "password"`：静态密码保护，无需浏览器 SSO。
- 密码以 **Machine 级环境变量** `OPENCLAW_GATEWAY_PASSWORD` 提供（S4U 早期即可读取）。
- `bind = "loopback"`：仅监听 127.0.0.1，公网仅经 Tailscale Funnel（TLS）暴露。

## 5. 成本控制 / 安全模式（重点）
网关无人值守，需防止自动任务烧 LLM 费用。本仓库提供一键开关：
```powershell
# 进入安全模式：备份并清空 DashScope key、关 dreaming/自动更新/入站渠道、关 funnel
powershell -File "E:\OpenClawGateway\disable-openclaw-api.ps1"
# 恢复使用：还原 key 与渠道，重启网关并健康检查
powershell -File "E:\OpenClawGateway\enable-openclaw-api.ps1"
```
详见 [SCRIPTS.md](SCRIPTS.md)。安全模式下网关照常开机自启、监听 18789，
但**任何模型调用因无 key 立即失败 → 零花费**。

## 6. 渠道与命令权限（安全须知）
- Telegram / 飞书 / Google Chat 通过 `openclaw.json > channels` 配置。
- **务必收紧白名单**：`allowFrom` 只放自己的用户 ID，切勿使用 `"*"`；
  `dmPolicy` 不要长期 `open`。
- `commands.bash/native` 开启意味着聊天可在本机执行命令——仅在可信白名单下启用。
- 命令所有者限制：`commands.ownerAllowFrom`。

## 7. 自动更新
- 配置项：`update.auto.enabled`、`update.channel`（`stable|beta|dev`）、`update.checkOnStart`。
- 查看：`openclaw update status`；执行：`openclaw update --yes`。
- 生产/常驻建议用 **stable** 通道，避免 beta 引入不稳定。

## 8. 灾难恢复（重装系统后）
```powershell
winget install OpenJS.NodeJS.LTS
npm install -g openclaw
# 还原 $HOME\.openclaw\ 备份（含 openclaw.json、auth-profiles.json、credentials）
[System.Environment]::SetEnvironmentVariable('OPENCLAW_GATEWAY_PASSWORD','<password>','Machine')
openclaw daemon install            # 或运行 openclaw_silent_boot_guardian.ps1
```

## 9. 运维速查
```powershell
Test-NetConnection 127.0.0.1 -Port 18789                       # 端口探测
Get-Content "C:\Users\10979\.openclaw\gateway.log" -Tail 50 -Wait
openclaw daemon status ; openclaw status ; openclaw doctor
Get-ScheduledTask "OpenClaw Gateway","OpenClaw Heartbeat" | ft TaskName,State
```

## 10. 文件清单
```
E:\OpenClawGateway\
├── README.md
├── openclaw_silent_boot_guardian.ps1   静默开机自启重注册脚本
├── openclaw_heartbeat.ps1              15 分钟端口看门狗
├── openclaw_update.ps1                 全局升级 + 重启 + 健康检查
├── openclaw_run_hidden.vbs             零窗口启动包装器
├── openclaw_task.xml                   计划任务定义备份
├── disable-openclaw-api.ps1            进入安全模式(零花费)
├── enable-openclaw-api.ps1             恢复 API 使用
├── tools\                              配置助手脚本（模型/提供方/思考/备份/状态）
└── docs\OPENCLAW.md / USAGE.md / SCRIPTS.md / MAINTENANCE.md / AUDIT.md
└── logs\                               运行时日志(gitignored)
```
