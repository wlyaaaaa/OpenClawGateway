# 收尾修复（2026-06-20 晚）

## 已修
1. **飞书/Telegram 不能对话** → 真因=安全模式把渠道 enabled=false 了（token 完好，config get 只是脱敏显示）。已重开 telegram+feishu，**手机已可用**。
2. **版本** → 已是最新 `2026.6.8`（up to date），无需更新。
3. **Funnel 公网访问** → 已重开。**网址 = https://wly.tailbe620b.ts.net** → 代理 127.0.0.1:18789。
4. **干扰的 env key** → 发现 `OPENAI_API_KEY` 环境变量是**无效的另一把 key（401）**，与配置 key 不一致，OpenClaw 优先用它出错。**已删除该环境变量**，全员统一用配置 key。

## 真相：为什么"默认不是 0520"
- `models status` 的 Default 确实是 **0520**（配置正确）。
- 但 **0520 的免费额度已耗尽**（实测 403 "The free tier of the model has been exhausted"），系统就退到**仍有额度的 preview**。
- preview / qwen3-max-2026-01-23 **仍有额度**。
- **解法**：你在阿里云给 0520 加额度/开通支持（你说会做）→ 0520 即恢复。默认配置已是 0520，无需我改。

## 待你处理（只有你能做）
- **0520 加额度**（阿里云）→ 默认即用 0520。在此之前若要系统能用，可临时 `/model set openai/qwen3.7-max-preview`（有额度）。
- **dashboard 输网关密码**：浏览器开 http://127.0.0.1:18789 → 右上/设置(齿轮)里 **Settings → Gateway Password** 填你的网关密码（即 Machine 环境变量 `OPENCLAW_GATEWAY_PASSWORD` 的值）→ 保存。否则一直 password_missing，且 "unknown parent session" 也因旧会话失效——**输密码 + 点"新会话"即清除**。
- **公网无需翻墙的方案**：Tailscale Funnel 要 VPN；想免翻墙可改 **Cloudflare Tunnel(cloudflared)**——免费、给公网 https 域名、国内可直连。需要我搭我可以做。

## 当前状态
模型默认 0520（额度待充）· preview/01-23 有额度 · 渠道 telegram/feishu 开 · Funnel 开(URL 见上) · 版本最新 · env key 冲突已清。
