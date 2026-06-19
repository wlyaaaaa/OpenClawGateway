# 日常使用指南

> 适配：OpenClaw v2026.6.8 + DashScope/Qwen。
> **默认即最强**：默认模型 `qwen3.7-max-2026-06-08` + 思考等级 `max`（追求能力，不为省钱妥协）。
> 当前 API 处于**安全模式**（key 已清空、零花费）；要用机器人先 `enable`。

## 0. 开始使用
```powershell
# 点亮机器人（还原 key、启用 Telegram 白名单、开 funnel、重启）
powershell -ExecutionPolicy Bypass -File E:\OpenClawGateway\enable-openclaw-api.ps1
```
然后手机 Telegram 给 bot 发消息即可。用完若想零花费：`disable-openclaw-api.ps1`。

## 1. 模型与思考（默认已拉满）
- 默认就是最强推理模型 + 最高思考；一般无需手动调。
- 临时换模型/降思考（省 token 或加速）用斜杠命令或脚本：
```powershell
.\tools\switch-model.ps1 -Model qwen-max -Thinking medium   # 临时换轻量
.\tools\switch-model.ps1 -Model qwen3.7-max-2026-06-08 -Thinking max   # 切回最强
```
- **新模型上线**（阿里出新版）时：`.\tools\switch-model.ps1 -Model <新id> -Register`。

## 2. 常用斜杠命令（聊天框直接发）
| 命令 | 作用 |
|------|------|
| `/new` | 重置会话。**长对话会 context overflow（历史崩溃根因），换任务就 /new** |
| `/model` ｜ `/model set <id>` | 查看 / 切换模型 |
| `/think off\|low\|medium\|high\|max` | 临时调思考深度 |
| `/reasoning on\|off` | 显示 / 隐藏思考过程 |
| `/settings` ｜ `/doctor` | 配置看板 / 自检 |

## 3. 手机 ChatOps（核心玩法）
手机 Telegram 给 bot 下任务，它在 Win11 后台执行，结果回传聊天框。
例：“用本地 cline 打开 bilibili 截图保存到 E:\ClineAgent\test.png，完成后把图发我”。
OpenClaw 收到 → 调本机 Cline CLI → 截图 → 回传。

## 4. 渠道与安全
- 当前只用 **Telegram**，白名单仅你的 ID（`8320970051`，已去 `"*"`）。
- 飞书 / Google Chat 默认关；要用先填**正确白名单**（飞书用 open_id，别用 `"*"`）再启用。
- `commands.bash` 开着＝聊天可在本机执行命令，务必只对可信白名单开放。

## 5. 成本与稳定（信息参考，不强制）
- 你优先“最强”，默认已最强；如某段时间想省，临时用 `qwen-max` + `/think low`。
- `memory-core.dreaming` 默认**关**（开=后台自动思考会持续花费）。
- 长期不用就 `disable`（安全模式，零花费）。
- Node 堆已设 1536MB，重载多渠道时更不易 OOM。

## 6. 一屏自检
```powershell
.\tools\status.ps1     # 版本/网关/任务/模型/思考/API模式/渠道/Funnel
```
