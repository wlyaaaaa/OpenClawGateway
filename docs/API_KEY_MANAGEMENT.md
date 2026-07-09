# OpenClaw Gateway API 凭据管理与安全模式指南

本指南旨在详细说明 OpenClaw 网关中大模型 API 凭据（API Key）的解析机制，以及如何使用提供的脚本进行快速配置与安全模式（成本控制模式）的切换。

---

## 一、 凭据解析机制与存储层次（避坑指南）

OpenClaw 网关的凭据解析是有严格的优先级和覆盖关系的，这也是导致之前“修改了 `openclaw.json` 中的 key 但网关依然请求旧配置”的根本原因。

### 1. 凭据查找优先级
当网关尝试调用大模型时，它会按以下顺序查找 API Key：
1. **环境变量**（如命令行中设置的 `OPENAI_API_KEY`，通常关闭）。
2. **SQLite 数据库凭据实体**（活跃主脑存储：`~\.openclaw\agents\main\agent\openclaw-agent.sqlite` 中的 `auth_profile_store`）。
3. **全局凭据备份文件**（`~\.openclaw\auth-profiles.json`）。
4. **模型提供商配置**（`~\.openclaw\openclaw.json` 中的 `models.providers.openai.apiKey`）。

> [!WARNING]
> **关键陷阱**：只要 `openclaw-agent.sqlite` 数据库中已经存在以 `<provider>:default`（例如 `openai:default`）命名的凭据 Profile，OpenClaw 就会**固执地一直读取此数据库记录**。此时，您就算把 `openclaw.json` 里的 `apiKey` 改上一百遍，网关也不会生效。

### 2. 编码与格式要求
- **无 UTF-8 BOM 头部**：OpenClaw 的 JSON 解析器不支持带 BOM 的 UTF-8 编码。在 Windows PowerShell 5.1 下使用 `Set-Content -Encoding utf8` 写入的 JSON 文件会自带 BOM 标记，导致 OpenClaw 解析错误。**必须**使用 BOM-Free 的 UTF-8 写入。
- **变量内插限制**：在 PowerShell 5.1 脚本编写时，诸如 `"$Provider:default"` 的字符串由于冒号 `:` 会被错误识别为命名空间变量，导致变量名失效。必须使用 `"${Provider}:default"` 的大括号转义语法。

---

## 二、 如何全局设置 / 更改 API 凭据

我们已经重构了根目录下的 `set-api.ps1` 脚本，它会**一站式修改所有受影响的文件**，并且直接越过 OpenClaw 缓慢的同步机制，把新密钥安全同步到 SQLite 数据库中。

### 1. 常用命令
请在 `E:\Projects\Tools\OpenClawGateway` 根目录下，以 **管理员身份** 打开 PowerShell 执行：

* **查看当前正在使用的所有端点和密钥（安全打码）**
  ```powershell
  .\set-api.ps1 -Show
  ```
* **一键更新通义千问 (DashScope) 密钥与模型，并自测连通性（最常用）**
  ```powershell
  .\set-api.ps1 -BaseUrl "https://dashscope.aliyuncs.com/compatible-mode/v1" -Key "sk-ws-H.RYXLMXL..." -Model "qwen3.7-plus" -Test
  ```
* **单项更新模型（仅切换默认模型）**
  ```powershell
  .\set-api.ps1 -Model "qwen3.7-plus"
  ```

### 2. 多套厂商配置（档案管理器）
如果您在多套大模型厂商（如阿里通义、DeepSeek 等）之间来回切换，可以使用 `-Save` 和 `-Profile` 快速存取，免去每次都要复制 BaseUrl 和 Key 的烦恼：
* **保存当前配置为名为 `qwen` 的档案**：
  ```powershell
  .\set-api.ps1 -Save qwen
  ```
* **查看已保存的所有提供商档案列表**：
  ```powershell
  .\set-api.ps1 -List
  ```
* **一键切换并应用 `deepseek` 档案配置**：
  ```powershell
  .\set-api.ps1 -Profile deepseek
  ```
> 档案数据存储在本地不入 Git 的 `.secrets\providers.json` 中。

---

## 三、 “安全更新脚本”：`api.ps1`（一键开关 API 成本控制）

这个脚本被称为**“成本安全守卫”**。它能帮您快速在“安全省钱模式”（停用 API）和“正常响应模式”（启用 API）之间切换。

### 1. 为什么需要它？
OpenClaw 机器人在后台可能会有自动的 Memory 整理、定时思考任务（如 `memory-core.dreaming`）或者接收外界 Telegram 的随机请求。为了防止在无人值守时大笔消耗 Token 扣费，可以通过该脚本一键切入**零 LLM 花费的“安全模式”**。

### 2. 使用方法
在根目录下运行：

* **`.\api.ps1 off` — 进入安全省钱模式**
  1. 自动将当前活跃的 `auth-profiles.json` 备份到 `secrets-backup\<时间戳>\`。
  2. **强行清空本地的所有 API Key**，使任何大模型调用因无 Key 立刻失败，实现 0 扣费。
  3. 保持 Telegram / 飞书的 `enabled` 长期开关不变，只关闭后台 Dreaming 思考，停止 Tailscale 穿透，避免 API key 脚本破坏 IM 可用性。
  4. 重启网关。

* **`.\api.ps1 on` — 退出安全模式，恢复 API**
  1. 自动寻找最近一次的密钥备份，将其还原回 `auth-profiles.json`。
  2. 保持 Telegram / 飞书的 `enabled` 长期开关不变，并收敛 Telegram 白名单至您个人的账号 ID（防他人蹭用）。
  3. 重启网关并进行连通性探活。

* **`.\api.ps1`（不带参数） — 翻转状态**
  - 如果目前处于开启状态则自动关闭，如果处于关闭状态则自动开启。

* **`.\api.ps1 status` — 查看当前网关的全面状态**
  - 打印详细的网关版本、监听端口、模型列表、当前的 API 状态（是否在安全模式内）以及连接白名单。

---

## 四、 常见问题排查与修复

1. **改了 Key 但 `openclaw models status` 仍然显示旧的或 `ollama`？**
   - 解决方案：运行一遍 `.\set-api.ps1` 加上参数配置，脚本中的 Python 刷写程序会自动把新 Key 强行写入 `openclaw-agent.sqlite` 数据库中并覆盖缓存。

2. **提示网关未监听 `18789`？**
   - 原因：网关重启需要大约 5-10 秒完成初始化和插件热加载。如果在重启瞬间做测试可能会报此错。
   - 解决方案：稍等片刻，运行 `openclaw health` 看到 `Gateway event loop: ok` 即可，或者运行 `.\tools\status.ps1` 查看状态。

3. **配置文件被破坏导致网关报错？**
   - 解决方案：运行 `.\tools\restore-config.ps1 -Latest` 可以从最近一次的自动备份中一键还原全部配置文件。
