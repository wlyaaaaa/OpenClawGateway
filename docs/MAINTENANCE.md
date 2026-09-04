# 维护、更新与恢复

## 日常只读检查

```powershell
pwsh -NoProfile -File .\tools\status.ps1
pwsh -NoProfile -File .\api.ps1 status -Json
pwsh -NoProfile -File .\tools\managed-component.ps1 -Status -Json
pwsh -NoProfile -File .\openclaw_silent_boot_guardian.ps1 -Json
```

保持以下证据分离：

- 当前 Gateway RPC/health；
- Windows 计划任务当前 State；
- 计划任务历史 LastTaskResult；
- 模型路由与认证；
- 真实消息或模型调用。

当前 Gateway 可以健康运行，同时保留一次非零历史调度回执；这不是自相矛盾，也不能被合并成一个“全绿”。

## 心跳

`openclaw_heartbeat.ps1` 先做官方健康检查：

- 健康：退出 0，不重启；
- 无监听者：走官方 start；
- 单一但不健康的 loopback 监听者：走官方 safe restart；
- 多监听或非 loopback：失败关闭，避免误杀其他进程。

## AI 编排、人在边界授权的受控更新

自动更新任务保持 disabled。只读状态不会升级：

```powershell
pwsh -NoProfile -File .\tools\managed-component.ps1 -Status -Json
```

只有明确决定更新，并接受备份、停止、安装和重启这些动作后，才在管理员 PowerShell 运行：

```powershell
pwsh -NoProfile -File .\openclaw_update.ps1
```

更新器按 relation（版本关系）处理：

- `equal`：不重装，只做后验；
- `ahead`：不降级；
- `unknown` / `channel_mismatch`：不开始事务；
- `behind`：官方备份 → 前检 → 官方更新 → 拉起 → 配置/RPC/模型/任务后验；
- 安装已改变但后验失败：返回 `partial`，不自动回滚到旧运行时。

支持 `stable`、`extended-stable`、`beta`、`dev` 四个官方通道。`extended-stable` 使用 `--channel extended-stable` 的精确选择，不与 `--tag` 混用；详见 [OpenClaw Update CLI](https://docs.openclaw.ai/cli/update)。

## 备份

```powershell
pwsh -NoProfile -File .\tools\backup-config.ps1 -Json
```

回执只有在 OpenClaw 官方 `backup create --verify` 成功后才返回 `ok=true`。结果归档包含私人状态，禁止提交到公开仓库。
默认写入用户目录下的 `OpenClawBackups`；可用 `OPENCLAW_BACKUP_DIR` 改到其他私人位置，但不能放进 `.openclaw` 源状态目录本身。

### 私人状态备份调度

当前是 3 个 Windows 计划任务承载 4 个消费者：

- `Codex Memory Backup`：20:05 与 22:05，由独立 `codex-memory` Owner（负责人）运行 Codex 小型可读状态备份；本仓库不实现或注册它。
- `Gemini Memory Backup`：20:10 与 22:10，运行 Gemini 小型可读状态备份并传播退出码。
- `OpenClaw Memory Backup`：20:20 与 22:20；先运行 Claude 项目记忆备份，再运行 OpenClaw 配置/工作区备份。即使前段失败，后段仍会尝试；两段结束后优先传播 Claude 的非零结果，否则传播 OpenClaw 结果。

因此 `OpenClaw Memory Backup` 非零只能说明共享链至少一段失败，不能仅凭计划任务结果判断是哪一个消费者；需要查看两段各自的脱敏日志。三项任务的任务结果只是各自最近一次运行回执，不能跨 Owner（负责人）相互代替。

## 恢复演练

```powershell
pwsh -NoProfile -File .\tools\restore-config.ps1 `
  -From <archive> `
  -Target <fresh-directory> `
  -Json
```

脚本先官方 verify（验证），再恢复到全新暂存目录。目标已经存在、归档损坏、输出无法读取时均失败；不会停 Gateway 或覆盖现役配置。离线激活需另行明确执行。

完整灾备激活必须按 [OpenClaw Backup CLI](https://docs.openclaw.ai/cli/backup) 的官方离线顺序执行：停 Gateway、选择暂存状态作为新状态目录或离线替换、运行 doctor（诊断）、重新启动并验证 health。该激活会改变现役状态，本轮没有执行；暂存测试和归档 verify 不能替代它。

## 常见判断

| 现象 | 先看什么 | 不能直接下的结论 |
|---|---|---|
| 端口存在 | Gateway RPC + health | 端口存在不等于 Gateway 健康 |
| 渠道 enabled | 真实入站与回发 | enabled 不等于消息 E2E 通过 |
| 默认本地模型 | 远程路线、会话固定模型、计划任务 | 默认本地不等于全局零费用 |
| stable 有新版本 | 当前 health、更新授权与窗口 | behind 不等于当前已坏 |
| restore 暂存成功 | 激活步骤与重启后验 | 暂存成功不等于现役恢复完成 |
