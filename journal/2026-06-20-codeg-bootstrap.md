# 收尾2:飞书报错 / 0517默认 / 设备配对 / codeg

## 已修
1. **飞书报错 `dir BOOTSTRAP.md failed`** → BOOTSTRAP.md 不存在导致。**已创建** `~/.openclaw/workspace/BOOTSTRAP.md`。
2. **默认模型 0517** → OpenClaw primary + Cline 都设为 `qwen3.7-max-2026-05-17`(实测有额度)。手机+电脑统一。
3. **设备配对** → 批准了挂起的 device pairing(`49465685...`),解开 scope upgrade 阻塞(影响 cron 删除、codeg 连接等)。
4. **坏 env key 来源定位** → codeg 的"Agent SDK管理"给 Cline 注入了 `OPENAI_API_KEY=...McGPQ9Ao`(无效 401)。需在 codeg UI 改成有效 key 或删除。

## codeg 连 OpenClaw(主优先级)
- codeg 的 OpenClaw 配置里 Gateway URL 是占位符 `wss://gateway-host:18789`，应改为 **`ws://127.0.0.1:18789`**。
- auth.mode=password → codeg 需提供网关密码；设备配对已批准。
- Cline 的 env 里 OPENAI_API_KEY 是坏的，改成有效 key + OPENAI_MODEL=qwen3.7-max-2026-05-17。

## 缓存能力
- session pruning(ttl 30m)已开 = 短时对话内**自动裁剪旧工具输出，不重复发送**。
- prompt 缓存(cacheRetention=long)已配，但当前 MaaS 端点不返回 cached_tokens（无收益）；dashscope 端点支持。
