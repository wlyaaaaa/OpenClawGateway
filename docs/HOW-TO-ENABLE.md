# 如何开关 OpenClaw 的 API（防烧钱安全模式）

OpenClaw 网关会 **24 小时常驻 + 开机自启**。为避免无人值守时自动任务（dreaming、
定时任务、陌生人私聊）消耗你的 **DashScope / Qwen 费用**，本仓库提供一对一键脚本。

## 当前状态：安全模式（API 已禁用）
- 网关照常开机自启、监听 `127.0.0.1:18789`，控制台可访问（需密码）。
- 但 **DashScope API key 已被清空并备份** → 任何模型调用立即失败 → **零花费**。
- 入站渠道（Telegram/飞书/Google Chat）全部关闭，Tailscale 公网入口已复位。
- 备份位置：`E:\OpenClawGateway\secrets-backup\<时间戳>\`（已 gitignore，不会上传）。

## 我想重新使用机器人 → 运行 enable
以**管理员** PowerShell：
```powershell
powershell -ExecutionPolicy Bypass -File "E:\OpenClawGateway\enable-openclaw-api.ps1"
```
它会：还原 API key → 重新启用 Telegram（**仅你的 ID 白名单**，已永久去掉 `"*"`）→
更新通道设为 stable → 开启 Tailscale funnel → 重启网关并健康检查。
完成后给你的 Telegram 机器人发条消息，应能正常回复。

> 飞书 / Google Chat 与 `dreaming` 默认保持关闭以省钱。如需飞书，请先在
> `C:\Users\10979\.openclaw\openclaw.json` 把 `channels.feishu.allowFrom`
> 填成你的飞书 open_id（不要用 `"*"`），再把 `enabled` 设为 `true`。

## 我又不用了 / 担心烧钱 → 运行 disable
```powershell
powershell -ExecutionPolicy Bypass -File "E:\OpenClawGateway\disable-openclaw-api.ps1"
```
重新进入安全模式（备份并清空 key、关渠道、关 funnel、零花费）。

## 验证零花费
```powershell
# key 应为空字符串
Get-Content "C:\Users\10979\.openclaw\auth-profiles.json"
# 渠道应为 false
openclaw config get channels.telegram.enabled
```

## 重要安全提醒
- 你的 Telegram Bot Token 曾被提交到公开仓库（已从 HEAD 移除，但 git 历史仍可查）。
  启用后白名单只放你的 ID，陌生人即使有 Token 也**无法触发任何动作**，风险已大幅降低。
  若想彻底安心，去 BotFather 用 `/revoke` 重新签发 Token，再更新
  `channels.telegram.botToken`（几十秒）。
- 切勿把 `auth-profiles.json` / `openclaw.json` / `.env` / `config.yml` 提交到任何仓库。
