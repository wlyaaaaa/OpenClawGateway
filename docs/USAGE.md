# 如何更好地使用 OpenClaw（日常 + 省钱指南）

> 适配：Windows 11 + OpenClaw v2026.6.8 + 阿里云 DashScope/Qwen。
> 当前默认为**安全模式**（API 关闭、零花费）。要用机器人，先 `enable`。

## 0. 一句话工作流
> 要用 → 跑 `enable-openclaw-api.ps1`（管理员）→ 手机 Telegram 发消息 → 用完不放心就 `disable`。

## 1. 💰 省钱三件套（最关键）
1. **默认用便宜模型**：已把默认模型设为 `qwen-max`（资源包全额抵扣，≈免费）。
   只有需要硬核推理/复杂 debug 时，再临时切：`/model set openai/qwen3.7-max-2026-06-08`
   （5 折自费），用完 `/model set openai/qwen-max` 切回。
2. **压低思考深度**：`/think off`（最省）→ `/think low|medium` → `/think high|max`（最贵）。
   日常聊天/查询用 `off` 或 `low`；只有复杂代码、系统排障才 `high/max`。
3. **勤开新会话 `/new`**：长对话会累积到 **context overflow**（Qwen 上限约 96k tokens，
   之前网关崩溃就有这个原因）。换任务就 `/new`，既省 token 又防大模型“失忆犯傻”。

## 2. 常用斜杠命令（聊天框直接发）
| 命令 | 作用 |
|------|------|
| `/new` | 重置/开启干净的新会话（省 token） |
| `/model` ｜ `/model set <id>` | 查看/切换模型 |
| `/think off\|low\|medium\|high\|max` | 调思考深度（直接影响花费） |
| `/reasoning on\|off` | 显示/隐藏思考过程（off 更清爽） |
| `/settings` | 查看当前模型、插件、状态看板 |
| `/doctor` | 触发网关自检 |

## 3. 📱 手机 ChatOps（核心玩法）
手机 Telegram 直接给 bot 下任务，它在 Win11 后台执行，结果回传到聊天框。
例：“用本地 cline 打开 bilibili 截图保存到 E:\ClineAgent\test.png，完成后把图发我”。
OpenClaw 收到 → 调本机 Cline CLI → 截图 → 回传。躺着也能干活。

## 4. 🔐 渠道与安全
- 只用 **Telegram**，白名单仅你的 ID（`8320970051`，已配置，已去掉 `"*"`）。
- 飞书 / Google Chat 默认**关闭**；要用先在 `openclaw.json` 填**正确的渠道白名单**
  （飞书用你的 open_id，别用 `"*"`）再 `enabled:true`。
- 切勿让陌生人能触发 bot —— 既烧钱又有安全风险。

## 5. 🔄 自动更新（已配好）
- **每周日 04:00** 计划任务 `OpenClaw Update` 自动 `npm install -g openclaw@latest`（stable 通道），
  **不阻塞开机**（避免早期网络未就绪导致的启动崩溃）。
- 想立刻更新：管理员运行 `openclaw_update.ps1`。
- 看更新通道：`openclaw update status`。

## 6. 🩺 健康与排查
```powershell
openclaw status            # 网关/渠道/模型/会话状态
openclaw doctor            # 自检并提示修复
openclaw daemon status     # 服务安装状态 + 连通性探测
Get-Content C:\Users\10979\.openclaw\gateway.log -Tail 50 -Wait
Get-ScheduledTask -TaskName 'OpenClaw *' | ft TaskName,State
```

## 7. 🧠 进阶省钱/稳定建议
- `memory-core.dreaming` 默认**关**（开启=后台自动思考，会无人值守烧钱）。需要“自动记忆/总结”再按需开。
- 长期不用就 `disable-openclaw-api.ps1` 回到安全模式（零花费），用时再 `enable`。
- 已把 Node 堆上限调到 1536MB，活跃多渠道时更不易 OOM 崩溃。
