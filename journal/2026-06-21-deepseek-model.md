# 2026-06-21 — 登记并启用 deepseek-v4-pro 默认模型

## 1. 任务背景与目标
- 用户请求登记 `deepseek-v4-pro` (用户描述为 `deepseek4.0Pro`) 模型并将其设为默认模型，提供 API 密钥 `<DEEPSEEK_API_KEY_REDACTED>`。
- 需要以脚本化方式自动修改 OpenClaw 配置文件、密钥文件、系统环境配置文件及 Cline 客户端的 OpenAI 兼容端点配置，并使用计划任务重启网关服务。

## 2. 自动化工具与执行过程
为安全、格式正确地修改所有 JSON/YML 文件，我们创建了以下工具：
- **Python 配置更新脚本 (`tools/register_deepseek.py`)**：
  - 针对带有 UTF-8 BOM 的文件特别使用了 `utf-8-sig` 进行读取/写入，避免了 JSON 解析中的 BOM 报错。
  - 在修改前，自动将 `openclaw.json`、`auth-profiles.json`、`config.yml` 和 Cline 的 `providers.json` 备份到同一目录下带时间戳的 `.bak.<timestamp>` 文件中。
- **PowerShell 封装及生命周期控制脚本 (`tools/apply-deepseek.ps1`)**：
  - 引用 `tools/_common.ps1` 中的公用函数，在更新前先通过 `Stop-ScheduledTask` 优雅停止网关。
  - 配置更新完成后，通过 `Start-ScheduledTask` 调用计划任务重启 OpenClaw Gateway。

## 3. 配置更新细节
- **OpenClaw 主配置 (`C:\Users\10979\.openclaw\openclaw.json`)**：
  - 注册了 `deepseek` 作为新的大模型提供商（`baseUrl` 设为 `https://api.deepseek.com`，`api` 为 `openai-completions`）。
  - 在 `deepseek` 提供商的 models 列表中登记了 `deepseek-v4-pro`，并设置 `reasoning` 为 `true`，上下文限制等相关超参设置。
  - 将 `agents.defaults.model.primary` 设为 `deepseek/deepseek-v4-pro`。
  - 将 `auth.profiles` 对应关系登记 `deepseek:default` 指向 `deepseek` 提供商。
- **密钥库配置 (`C:\Users\10979\.openclaw\auth-profiles.json`)**：
  - 写入了新的 API 密钥凭据 `deepseek:default`，密钥为 `sk-ad6...`。
- **全局配置 (`C:\Users\10979\.openclaw\config.yml`)**：
  - 更新 `provider` 值为 `deepseek`，`api_key` 值为提供的 DeepSeek 密钥，`base_url` 值为 `https://api.deepseek.com`，`model` 值为 `deepseek-v4-pro`。
- **Cline 配置 (`C:\Users\10979\.cline\data\settings\providers.json`)**：
  - 将 OpenAI 兼容端点的 `apiKey`、`baseUrl` 及 `model` 均切换为 DeepSeek。

## 4. 问题排查与修复过程

在部署后测试中发现了两个问题并予以解决：

1. **UTF-8 BOM 头引发的凭据导入失败**：
   - **问题现象**：主 Agent (`main`) 在请求 DeepSeek 时报错 `No API key found for provider "deepseek" ... missing-provider-auth`。
   - **原因分析**：原 Python 脚本在写入配置文件时使用了 `utf-8-sig` 编码，导致写出的 JSON 文件带有了 UTF-8 BOM 头。当 OpenClaw 的 `JSON.parse` 去解析 `auth-profiles.json` 时抛出异常，并被其内部的 `tryReadJsonSync` 拦截返回 `null`，导致凭据无法自动导入到 SQLite 数据库中。
   - **解决方案**：
     - 修改 `register_deepseek.py` 使其写入时均统一使用标准的 `utf-8`（无 BOM）。
     - 创建并执行了 `tools/remove_bom.py`，彻底移除了 `openclaw.json`、`auth-profiles.json`、`config.yml` 及 Agent 下的备份文件的 BOM 头。
     - 重新执行 `openclaw doctor --repair --non-interactive` 成功将凭据自动迁移导入至 sqlite。

2. **`cost` 结构 Schema 校验未通过**：
   - **问题现象**：日志提示 `model catalog load issue: Invalid models.json schema - providers.deepseek.models.0.cost.cacheRead: must have required properties cacheRead, cacheWrite`。
   - **原因分析**：OpenClaw 要求如果提供了 model 的 `cost`，就必须提供完整的子属性（包括 `cacheRead` 与 `cacheWrite`）。
   - **解决方案**：在 `register_deepseek.py` 的模型定义 `cost` 中补全了 `"cacheRead": 0.000001` 和 `"cacheWrite": 0.000002`，再次应用配置重启后此警告消失。

## 5. 验证结果
- 再次运行 `openclaw doctor --repair --non-interactive` 提示凭证已成功迁移进入 SQLite 存储中。
- 运行 `openclaw daemon status` 返回：
  - `Connectivity probe: ok`
  - `Listening: 127.0.0.1:18789`
- 运行 `openclaw logs --limit 30` 验证确认网关无任何 Schema 校验错误或凭据读取失败警告。

