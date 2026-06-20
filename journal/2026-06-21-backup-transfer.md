# 2026-06-21 — 更新/转移/记忆备份确认 + 定时任务

> 用户要点：确认命令行更新（别点应用内更新）、确认新电脑可从 GitHub 转移、备份记忆、建定时任务（凌晨 4 点 + 白天）。

## A. 命令行更新（已确认）
- 原生 `openclaw update` 存在，但**会跑 doctor**（可能补回 `*` 白名单、把 api 改回 responses、重写 gateway.cmd）→ **绝不点应用内/原生更新**。
- 正道：`openclaw_update.ps1`（npm-only、不跑 doctor、更新后自愈 `api=openai-completions`）。
- `OpenClaw Update` 计划任务 = Disabled（故意），需要时手动跑脚本或启用。

## B. 新电脑从 GitHub 转移（已确认具备）
- `bootstrap/setup.ps1` + 脱敏双模板（openclaw/auth）+ `docs/DEPLOY.md` + README 克隆指令 + 公开远程，齐全。
- 流程：`git clone` 拉脚本/文档/模板 → `setup.ps1 -RestoreFrom <私有备份>` 还原密钥与记忆。
- 密钥/记忆**不在公开仓库**，从用户私有备份还原。

## C. 记忆备份（新增）
- 新脚本 `tools/backup-memory.ps1`：把 `C:\Users\10979\.claude\...\memory`（6 文件）复制到 `memory-backup\<时间戳>\`，保留最近 30 份，写 `logs\backup-memory.log`。
- `memory-backup/` 已加入 `.gitignore`（记忆含运维上下文，非原始密钥，**不入公开仓库**）。
- 已立即跑一次（成功，6 文件）。

## D. 定时任务（新增）
- 注册 `OpenClaw Memory Backup`：**每日 04:00 + 13:00**，S4U/Highest/Hidden/StartWhenAvailable。
- 实测：手动触发 LastTaskResult=0（成功），S4U 执行路径通。

## E. 文档同步
- 更新 `docs/MAINTENANCE.md`（任务表 + 备份策略 + 5.1 新电脑转移）、`docs/SCRIPTS.md`（backup-memory / setup-codeg-bridge）、`CLAUDE.md`（任务清单 + 更新只走命令行警告）。
- 重新生成 MAINTENANCE.pdf / SCRIPTS.pdf。

## F. 记忆云备份（追加，用户要求"云备份很必要"）
- 新建**私有**仓库 `wlyaaaaa/claude-memory`（gh repo view 实测 visibility=PRIVATE），本地工作目录 `E:\ClaudeMemoryBackup`。
- 上传前**脱敏**：`openclaw-secret-leak.md` 原本明文写了网关密码 → 改为"值见本机 env"；全量复扫 0 残留密钥后才上云。
- `backup-memory.ps1` 增云推送段：robocopy 镜像 .md → git add/commit/push。
- **踩坑**：`$ErrorActionPreference='Stop'` 下 git 的 LF/CRLF 警告走 stderr 被当错误抛 → 云推送失败。修复：git 调用全部 `2>$null` + 局部 EAP=Continue + 云仓库 `core.autocrlf false` + `.gitattributes * -text`。
- **端到端实测通过**：改 MEMORY.md → 跑脚本 → 日志 `[OK] 云备份已推送` → 云端新增 `memory snapshot` 提交；远程内容核实含最新、无明文密码。
- 新机恢复：`git clone claude-memory` → 拷 `*.md` 回 `.claude\...\memory\`。

## 当前计划任务全景
Gateway / Heartbeat / AutoPush / WeFlow Watchdog / **Memory Backup(04:00+13:00，本地+私有云)** = Ready；OpenClaw Update = Disabled（故意）。
