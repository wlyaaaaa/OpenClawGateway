# 脚本使用指南

所有脚本均为 **PowerShell**，编码 UTF-8 (BOM)。涉及计划任务/系统配置的请以
**管理员**身份运行。脚本分两类：根目录的「服务生命周期」脚本，`tools\` 下的「配置助手」脚本。

> [!NOTE]
> 关于大模型 API Key 凭据管理的详细细节、SQLite 同步原理解析以及安全模式的深度使用指南，请参阅独立的专题文档：[API 凭据管理与安全模式指南](API_KEY_MANAGEMENT.md)。

```
E:\Projects\Tools\OpenClawGateway\
├── api.ps1                             # ★快速：一键开关 API（on/off/toggle/status）
├── set-api.ps1                         # ★快速：全局设 key/模型/网站 + 提供方档案
├── openclaw_silent_boot_guardian.ps1   # 服务：重注册静默开机自启任务
├── openclaw_heartbeat.ps1              # 服务：端口看门狗（由计划任务调用）
├── openclaw_update.ps1                 # 服务：通道感知手动更新（任务默认 Disabled）
├── openclaw_run_hidden.vbs             # 服务：零窗口启动包装器
├── disable-openclaw-api.ps1            # 引擎：进入安全模式（零花费，被 api.ps1 调用）
├── enable-openclaw-api.ps1            # 引擎：恢复 API 使用（被 api.ps1 调用）
└── tools\
    ├── switch-model.ps1                # 切换默认模型 + 思考等级
    ├── set-thinking.ps1                # 设置思考等级与显示
    ├── backup-config.ps1               # 备份全部配置与密钥
    ├── restore-config.ps1              # 从备份恢复
    ├── status.ps1                      # 一屏状态面板
    ├── build_docs_pdf.py               # 文档导出 PDF（白色纯绿主题）
    └── restart_gateway.ps1             # 服务：异步安全重启网关（脱离进程树防自杀卡死）
```

---

## ★ 两个最常用快速脚本（根目录）

### `api.ps1` — 一键开关 API
```powershell
.\api.ps1 on        # 开启（还原 key + 保持 IM 渠道开关 + funnel，机器人可用）
.\api.ps1 off       # 关闭（清空 key + 保持 IM 渠道开关 + 关 funnel，零花费 API 安全模式）
.\api.ps1           # 不带参数＝自动判别并翻转
.\api.ps1 status    # 查看当前状态 + 完整面板
```
是 `enable/disable-openclaw-api.ps1` 的快捷前端，自动判别当前状态，记不住状态也不怕。

### `set-api.ps1` — 快速全局设 key / 模型 / 网站
> provider 固定 `openai`；**`api=openai-completions` 命门不改**（改成 responses 会让工具/技能 400 失败）。只动 key、模型、baseUrl。
```powershell
.\set-api.ps1 -Show                                          # 看当前
.\set-api.ps1 -Model qwen3.7-plus                              # 只换模型
.\set-api.ps1 -BaseUrl "https://xxx/v1" -Key "sk-xxx" -Model m -Test   # 全换 + 连通性自测
```
**提供方档案（优化）**：多家厂商配置存名一键切换，免反复输入。
```powershell
.\set-api.ps1 -Save dashscope        # 把当前配置存为档案 dashscope
.\set-api.ps1 -Profile deepseek      # 一键切到 deepseek 档案
.\set-api.ps1 -List                  # 列出所有档案
```
档案存于 `C:\Users\<USER>\.openclaw\.secrets\providers.json`。改动前自动备份，`-Test` 改后自测。

---

## 一、服务生命周期脚本（根目录）

### `openclaw_silent_boot_guardian.ps1`
重注册 `OpenClaw Gateway` 计划任务为 **BootTrigger+30s / S4U / Highest / Hidden**，
实现无登录、无黑窗的开机自启。装机或自启失效时运行一次。
```powershell
powershell -ExecutionPolicy Bypass -File .\openclaw_silent_boot_guardian.ps1
```

### `openclaw_update.ps1`
读取 `update.channel`（stable→`@latest`、beta→`@beta`、dev→`@dev`），**仅用 npm** 更新
（不触发 `openclaw update` 的 doctor，故不会覆盖自定义隐藏启动任务），比对版本→更新→重启→健康检查。
默认不自动运行；`OpenClaw Update` 任务保留但 Disabled，需要时手动：
```powershell
powershell -File .\openclaw_update.ps1
```

### `openclaw_heartbeat.ps1`
探测 `127.0.0.1:18789`，无响应则重启网关任务。由 `OpenClaw Heartbeat` 任务每 15 分钟调用。

### `disable-openclaw-api.ps1` / `enable-openclaw-api.ps1`（成本安全模式）
| 脚本 | 作用 |
|------|------|
| **disable** | 备份并**清空 DashScope key** → 零 LLM 花费；保持 Telegram/飞书 enabled 不变；关 dreaming/自动更新；收敛白名单；关 Funnel |
| **enable**  | 还原 key；保持 Telegram/飞书 enabled 不变；stable 通道；开 Funnel；重启 + 健康检查 |
```powershell
powershell -File .\disable-openclaw-api.ps1     # 闲时省钱
powershell -File .\enable-openclaw-api.ps1      # 要用时点亮
```
> 备份位于 `C:\Users\<USER>\.openclaw\secrets-backup\`。API key 脚本永远不改 Telegram/飞书的 `enabled` 开关；IM 是否在线由长期配置决定。

---

## 二、配置助手脚本（`tools\`）

### `switch-model.ps1` — 切换默认模型
```powershell
.\tools\switch-model.ps1 -List                                   # 查看当前与已注册模型
.\tools\switch-model.ps1 -Model qwen3.7-plus -Thinking max
.\tools\switch-model.ps1 -Model qwen4-max-2026-12-01 -Register   # 新模型上线：登记+切换
```
| 参数 | 说明 |
|------|------|
| `-Model <id>` | 目标模型（裸 id 默认归到 `openai/`；也可写全 `provider/id`） |
| `-Thinking <off..max>` | 顺带设思考等级 |
| `-Register` | 模型未登记时，自动加入 provider 的模型表 |
| `-List` / `-NoRestart` | 仅查看 / 改完不立即重启 |

> 更换提供方/端点/Key 用根目录的 **`set-api.ps1`**（见上方“两个最常用快速脚本”）。

### `set-thinking.ps1` — 思考等级
```powershell
.\tools\set-thinking.ps1 -Level max               # 最强推理（默认）
.\tools\set-thinking.ps1 -Level low -Reasoning off
```

### `backup-config.ps1` / `restore-config.ps1` — 备份恢复
```powershell
.\tools\backup-config.ps1                          # 打包配置+密钥到 secrets-backup\full-<时间戳>
.\tools\restore-config.ps1 -Latest                 # 从最新备份恢复（恢复前另存 .pre-restore）
```

### `status.ps1` — 状态面板
```powershell
.\tools\status.ps1     # 版本/网关/任务/模型/思考/API模式/渠道/Funnel 一屏看全
```

### `backup-memory.ps1` — 备份 Claude 记忆（本地 + 私有云）
```powershell
.\tools\backup-memory.ps1     # ①本地轮换快照 C:\Users\<USER>\.openclaw\memory-backup\claude\<时间戳>\（留30份）
                              # ②镜像并推送到私有云仓库 wlyaaaaa/claude-memory（E:\Projects\Backups\claude-memory）
```
计划任务「OpenClaw Memory Backup」每日 **20:20 + 22:20** 自动跑。记忆含运维上下文（**已脱敏，非原始密钥**），本地快照不入公开仓库；云备份在**私有**仓库。新机恢复：`git clone` claude-memory 后按项目目录把 `memory\*.md` 拷回对应 `C:\Users\<USER>\.claude\projects\<project>\memory\`。

### `setup-codeg-bridge.ps1` — 一键接 codeg
```powershell
.\tools\setup-codeg-bridge.ps1   # 把带网关密码的 openclaw-bridge MCP 写进 Cline 生效配置 + 探活
```
用于 codeg 控制台经 Cline 调用 OpenClaw（ACP 直连走不通）。详见 [CODEG.md](CODEG.md)。

### `restart_gateway.ps1` — 异步安全重启网关
```powershell
.\tools\restart_gateway.ps1      # 异步安全重启网关计划任务
```
由于 Windows 计划任务的强杀机制，直接在 OpenClaw 内核中或在子进程中运行 `/End` 会立即终止运行中的代码，从而导致无法继续执行随后的 `/Run`。该脚本通过 WMI 机制（`Invoke-WmiMethod`）在独立于当前计划任务进程树的后台拉起一个带有延迟的重启命令，安全且彻底地实现网关服务重新加载。

---

## 备注
- 多数 `tools\` 脚本会**重启网关**以即时生效；加 `-NoRestart` 可延后到下次启动。
- 标量配置经原生 `openclaw config set/patch` 校验写入，避免手改 JSON 出错。
- 密钥仅写入本机 `C:\Users\<USER>\.openclaw\`，**永不入库**。
