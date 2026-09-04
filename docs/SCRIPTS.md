# 脚本清单

## AI 与用户共用入口

| 文件 | 作用 | 默认是否写运行态 |
|---|---|---:|
| `api.ps1 status` | 汇总默认模型、远程路线和认证来源 | 否 |
| `tools/status.ps1` | 查看版本、Gateway、任务、模型、渠道和 Funnel | 否 |
| `openclaw_silent_boot_guardian.ps1` | 核对 Windows 常驻；`-Repair` 才重注册 | 否 |
| `openclaw_heartbeat.ps1` | 不健康时使用官方生命周期恢复 | 可能 |
| `openclaw_update.ps1` | 显式人工受控更新 | 是 |
| `tools/backup-config.ps1` | 创建官方校验归档 | 是，写私人归档 |
| `tools/restore-config.ps1` | 恢复到全新暂存目录 | 是，只写目标目录 |
| `tools/setup-codeg-bridge.ps1` | 保留现有配置并 upsert Cline MCP bridge | 是，写指定 Cline 配置 |

## 内部实现

- `tools/_common.ps1`：官方 Gateway 生命周期和 health 合同；
- `tools/_update_lib.ps1`：版本关系、外部进程超时与 JSON 原子写入；
- `tools/managed-component.ps1`：受控更新状态机；
- `tools/g-hot-snapshot.ps1`、`tools/git-cloud-sync.ps1`：现有私人备份消费者使用的热备与 Git 同步组件；
- `tools/private-backup-settings.ps1`：为本仓库仍有计划任务消费者的 Gemini、Claude 与 OpenClaw 备份脚本读取被 Git 忽略的本机路径配置；公开源码不保存私库坐标或磁盘拓扑；
- `tools/gemini_memory_backup_hidden.vbs`、`memory_backup_hidden.vbs`：本仓库拥有的 2 个隐藏计划任务入口。前者运行 Gemini；后者依次尝试 Claude 与 OpenClaw，并传播第一段非零，否则传播第二段结果。Codex 任务由独立 `codex-memory` Owner（负责人）实现；
- `tools/auto-archive-push.ps1`：公开仓库自动归档消费者，运行前执行公开内容门。

## 已退役入口

旧 `set-api.ps1`、`enable/disable-openclaw-api.ps1`、`switch-model.ps1`、`set-thinking.ps1`、`apply-*`、`register_*`、内部 SQLite 凭据写入器、机器专用 WeFlow 查询脚本、仓库内生成的启动 VBS、失效的 Cline bootstrap 资产、无消费者 Codex/PDF/BOM/restart 工具和无关 `public/` 站点已经删除。

删除原因不是“代码旧”本身，而是它们分别存在错误成本结论、跨 Owner 覆盖、占位凭据写入、私人数据残件、机器绑定或完全无当前消费者。Git 历史仍保留过去实现，不为旧测试继续维护废层。

## 测试

`tools/test-*.ps1` 使用隔离夹具。重点合同：

- 成本状态不能把仍有远程路线的系统显示为 `API OFF`；
- bootstrap 未填占位时不产生副作用；
- CodeG upsert 保留其他 MCP Server，畸形 JSON 不覆盖；
- Gateway 官方生命周期回执；
- 官方备份与 staging-only（只暂存）恢复；
- 受控更新的 equal/behind/ahead/partial；
- Git 同步的 clean/ahead/behind/diverged 与远端 OID 回读；
- 公开仓库无凭据形态、机器专用残件和坏文档链接。
