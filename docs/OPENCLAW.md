# 架构与运行边界

## 产品角色

OpenClawGateway 是 OpenClaw 在 Windows 上的公开脱敏运维层。OpenClaw 自己拥有会话、模型、渠道、工具与官方 Gateway CLI；本仓库补充 AI 可调用、人可读的结构化状态、Windows 常驻核对、心跳、受控更新、官方归档包装和可选 CodeG/Cline 接入。

主要消费者是 AI Agent（智能体）：它先读取状态与回执，再选择最窄的维护入口，并把真实结果、恢复点和未验项交给人。人不需要经常使用 OpenCode、CodeG 或终端；只有外部通信、付费调用、更新、修复注册和灾备激活等有影响动作才需要明确授权。CodeG/Cline 不可用时，状态、备份、更新和恢复能力仍然成立。

```text
消息渠道
  └─> OpenClaw Gateway（loopback）
        ├─> 本地模型
        ├─> 已配置的远程 Provider
        └─> 本地工具 / MCP
              └─> 结果回原渠道
```

## 生命周期

`tools/_common.ps1` 是脚本侧唯一 Gateway 生命周期实现：

- 健康以 `openclaw health --json --verbose` 的 `ok=true` 且事件循环未降级为准。
- 监听必须只有一个，并且只能绑定 loopback；非本机监听或多个监听者直接失败。
- 启动、停止和重启调用官方 `openclaw gateway` 命令。
- safe restart（安全重启）返回 deferred/coalesced（延迟或合并）时，不在请求进程里死等；后续由独立状态回读验收。

`openclaw_heartbeat.ps1` 只在不健康时启动或安全重启。`openclaw_silent_boot_guardian.ps1` 默认只读；`-Repair` 才重注册，优先走 PCConfig 受控启动器，通用环境走官方 `gateway install`。

## 模型与成本

当前默认模型是本地路线，但远程模型与认证仍存在。以下事情必须分开：

1. 默认、fallback（回退）、utility（辅助）与图像模型是不是本地；
2. `/model` 或已有会话还能否选择远程模型；
3. cron（定时任务）是否另有模型覆盖；
4. OpenClaw、环境变量或 Provider 是否仍有远程认证。

因此本仓库不再提供伪造的“全局 API OFF”。`api.ps1 status` 只读汇总这三个轴；真实变更交给官方 Models CLI，并在变更后重新核对会话、计划任务和路由。

## 渠道

当前观测到 Telegram、飞书为 enabled，Google Chat 为 disabled。这只证明配置开关。只有一次真实入站消息、Agent 执行与回发都成功，才能把某个渠道称为端到端通过；本轮没有发送外部消息。

## 更新

自动更新任务按设计 disabled。`tools/managed-component.ps1` 提供：

- `-Status -Json`：只读返回当前版、stable 目标版、版本关系和 Gateway 健康；
- `-Update -Json`：显式人工动作，依次完成官方备份、前检、官方更新、重新拉起和后验；
- 版本已改变但后验失败时返回 partial（部分完成），不自动降级。

“有新版本”不等于“当前运行坏了”。当前 `2026.8.1` 健康，稳定目标 `2026.9.1` 尚未安装。

## 恢复

备份和恢复只使用 OpenClaw 官方归档合同：

- `backup create --verify` 生成带 manifest（清单）的校验归档；
- `backup verify` 验证归档；
- `backup restore --target <fresh>` 恢复到全新暂存目录；
- 暂存完成不等于现役配置已激活，离线激活是另一项明确操作。

这避免了旧脚本直接复制认证文件、内部 SQLite 和凭据目录造成的版本漂移与半恢复。

## 公开边界

公开仓库可以说明产品名、通用命令、loopback 端口、公开 Provider 名与脱敏测试结果；不得保存账号、token、私有 URL、凭据位置全图、原始消息、日志正文或完整恢复材料。

当前 `openclaw doctor --json` 的三条 warning（警告）也按边界解释：两条来自未开放远程节点接入和未启用 device-pair（设备配对）插件，这不是本产品承诺；另一条只说明私人本机配置仍含承载秘密的字段。公开内容门证明这些值没有进入本仓库，但本轮没有跨 Owner 改写私人运行配置。
