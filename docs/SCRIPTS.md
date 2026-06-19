# 脚本使用指南

所有脚本均为 **PowerShell**，编码 UTF-8 (BOM)。涉及计划任务/系统配置的请以
**管理员**身份运行。脚本分两类：根目录的「服务生命周期」脚本，`tools\` 下的「配置助手」脚本。

```
E:\OpenClawGateway\
├── openclaw_silent_boot_guardian.ps1   # 服务：重注册静默开机自启任务
├── openclaw_heartbeat.ps1              # 服务：端口看门狗（由计划任务调用）
├── openclaw_update.ps1                 # 服务：通道感知自动更新
├── openclaw_run_hidden.vbs             # 服务：零窗口启动包装器
├── disable-openclaw-api.ps1            # 成本：进入安全模式（零花费）
├── enable-openclaw-api.ps1            # 成本：恢复 API 使用
└── tools\
    ├── switch-model.ps1                # 切换默认模型 + 思考等级
    ├── set-provider.ps1                # 更换 API 端点 / Key / 提供方
    ├── set-thinking.ps1                # 设置思考等级与显示
    ├── backup-config.ps1               # 备份全部配置与密钥
    ├── restore-config.ps1              # 从备份恢复
    └── status.ps1                      # 一屏状态面板
```

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
由 `OpenClaw Update` 计划任务每周调用，也可手动：
```powershell
powershell -File .\openclaw_update.ps1
```

### `openclaw_heartbeat.ps1`
探测 `127.0.0.1:18789`，无响应则重启网关任务。由 `OpenClaw Heartbeat` 任务每 15 分钟调用。

### `disable-openclaw-api.ps1` / `enable-openclaw-api.ps1`（成本安全模式）
| 脚本 | 作用 |
|------|------|
| **disable** | 备份并**清空 DashScope key** → 零 LLM 花费；关 channels/dreaming/自动更新；收敛白名单；关 Funnel |
| **enable**  | 还原 key；重新启用 Telegram（仅本人白名单）；stable 通道；开 Funnel；重启 + 健康检查 |
```powershell
powershell -File .\disable-openclaw-api.ps1     # 闲时省钱
powershell -File .\enable-openclaw-api.ps1      # 要用时点亮
```
> 备份位于 `secrets-backup\`（已 gitignore）。enable 默认**不**自动恢复飞书/dreaming，避免意外花费。

---

## 二、配置助手脚本（`tools\`）

### `switch-model.ps1` — 切换默认模型
```powershell
.\tools\switch-model.ps1 -List                                   # 查看当前与已注册模型
.\tools\switch-model.ps1 -Model qwen3.7-max-2026-06-08 -Thinking max
.\tools\switch-model.ps1 -Model qwen4-max-2026-12-01 -Register   # 新模型上线：登记+切换
```
| 参数 | 说明 |
|------|------|
| `-Model <id>` | 目标模型（裸 id 默认归到 `openai/`；也可写全 `provider/id`） |
| `-Thinking <off..max>` | 顺带设思考等级 |
| `-Register` | 模型未登记时，自动加入 provider 的模型表 |
| `-List` / `-NoRestart` | 仅查看 / 改完不立即重启 |

### `set-provider.ps1` — 更换提供方 / 端点 / Key
```powershell
.\tools\set-provider.ps1 -ShowOnly                                # 只看当前
.\tools\set-provider.ps1 -BaseUrl "https://xxx/v1" -Key "sk-xxx" -Model some-model
```
一步更新 `models.providers.<p>.baseUrl` + `auth-profiles.json` 的 key + 默认模型；改动前自动备份。

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
.\tools\status.ps1     # 版本/网关/三任务/模型/思考/API模式/渠道/Funnel 一屏看全
```

---

## 备注
- 多数 `tools\` 脚本会**重启网关**以即时生效；加 `-NoRestart` 可延后到下次启动。
- 标量配置经原生 `openclaw config set/patch` 校验写入，避免手改 JSON 出错。
- 密钥仅写入本机 `C:\Users\10979\.openclaw\`，**永不入库**。
