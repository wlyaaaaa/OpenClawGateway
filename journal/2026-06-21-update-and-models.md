# 2026-06-21 — OpenClaw 版本升级及默认模型调整（qwen3.7-plus）

## 1. 任务背景与目标
- **版本升级**：使用内置更新脚本安全将 OpenClaw 网关从 `2026.6.8` 升级到最新 `2026.6.9`。
- **模型重配**：默认主用模型改成最新 `qwen3.7-plus`，同时确保降级/备用模型依然保留 `qwen3-max-2026-01-23`（0123/0126）。
- **清空会话**：在不损坏网关结构的前提下，安全备份并清除现有所有的会话历史记录。
- **文档同步**：同步替换所有相关文档、脚本和模版里的旧默认模型 `qwen3.7-max-2026-05-17` 引用，并重新生成对应的 PDF 说明文档提交到 GitHub。

## 2. 自动化工具与执行过程

为实现配置的安全切换及防泄密保护，我们创建并运行了以下工具：
- **安全配置脚本 (`tools/register_qwen37plus.py`)**：
  - **防机密泄露**：针对前置的 `auto-archive-push.ps1` 守卫中对 `sk-ws-` 前缀的硬编码机密拦截机制，新脚本放弃了硬编码 API Key，改用在运行时从本地非代码目录下的 `auth-profiles.json` 动态读取凭据，彻底避免了秘钥意外入 Git。
  - 同步更新了 `openclaw.json` (默认主模型)、`config.yml` (兼容端点默认模型及网站) 和 Cline 的 `providers.json` (OpenAI 兼容端点配置)。
- **生命周期编排脚本 (`tools/apply-qwen37plus.ps1`)**：
  - 调用 `Stop-Gateway` 优雅停止网关释放文件锁。
  - 调用 Python 配置脚本更新三端配置。
  - **安全备份并清除会话**：将 `C:\Users\10979\.openclaw\agents\main\sessions\` 下的旧轨迹及会话文件整体移至带时间戳的 `C:\Users\10979\.openclaw\session-backup-20260621-150158/` 进行归档，然后清空会话。
  - 调用 `Start-Gateway` 重启网关，并自愈校验。

## 3. 文档及 PDF 重新编译
- 批量替换了 `README.md`、`docs/CODEG.md`、`docs/OPENCLAW.md`、`docs/SCRIPTS.md`、`docs/USAGE.md` 以及 `bootstrap/skills/cline-coding/SKILL.md` (包括 active workspace 下的副本) 中关于老版本默认推理模型 `qwen3.7-max-2026-05-17` 的字面引用为 `qwen3.7-plus`。
- 运行 `python tools/build_docs_pdf.py` 重新编译生成了对应的 PDF 格式说明书。
- 所有修改均成功通过了 `git diff --cached` 内部机密扫描干涉，无警告，并成功推送至 GitHub 仓库。

## 4. 验证结果
- 网关成功升级，主版本升级至：`OpenClaw 2026.6.9 (c645ec4)`。
- 运行 `openclaw health` 返回结果：
  - 成功监听到 `18789` 端口。
  - 会话列表已重置清零：`Session store (main): ...sessions.json (1 entries)`（仅包含本次启动初始连接）。
  - 各渠道及外部控制台已全部自动适配加载最新 `qwen3.7-plus` 模型。
