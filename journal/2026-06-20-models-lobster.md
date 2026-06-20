# 工作日志 — 模型切换 / Cline 修复 / Lobster

> 注：本轮涉及的 LLM 端点与模型名属临时且易变，按要求**不在文档写死**，此处仅记通用结论。

## 预先任务清单
1. 用付费/免费额度实测怎么省 OpenClaw（含 Cline）的 token
2. OpenClaw 切到新（免费额度）端点/模型并实测正常
3. Cline 同步切换并检查是否正常
4. 实测 prompt 缓存是否可省 token
5. 安装并启用 Lobster
6. 回顾前几轮，做不降智的安全省 token，归档自动推送

## 完成报告
| # | 任务 | 结果 |
|---|------|------|
| 1 | 实测省 token | 见下「有效杠杆」；缓存无效（端点不暴露） |
| 2 | OpenClaw 切端点 | 切到新免费端点 + 预览推理模型，`openclaw agent` 实测**正常回复** |
| 3 | Cline 正常性 | ✅ 正常：清掉污染的 `azure.apiVersion` 字段后，Cline 在新端点正常工作，**且遵守全局规范（输出极简）** |
| 4 | prompt 缓存 | ⚠️ 此端点对重复前缀**不返回 `cached_tokens`**（3.6/3.7 预览都试过），无法测出收益，**未启用**（避免不可验证的改动） |
| 5 | Lobster | ✅ 内置工具 `tools.alsoAllow:["lobster"]` + ClawHub `lobster` 技能，Ready+可见，复杂多步任务联想它，省工具调用 token |
| 6 | 回顾/省 token | 见下 |

## 关键修复（本轮排障）
- **Cline 的真实配置在 `providers.json → providers.openai-compatible.settings`**（不是 globalState）。其中一个迁移残留的 `azure.apiVersion=<模型名>` 字段会污染请求 → 报 `overdue-payment/access denied`。**清除该字段后恢复正常**。
- **老 dashscope 端点整体欠费**（所有模型 access denied）；故委托命令里**去掉硬编码 `-m <模型>`**，改用 Cline 配置的默认模型（model-agnostic，且不写死易变模型名）。

## 有效的省 token 杠杆（不降智，已就位）
- **adaptive 思考**：难题自动拉满（最高思考可用），闲聊降档，省最贵的思考 token。
- **session pruning (ttl 30m)**：只裁旧工具输出，对话无损。
- **委托 Cline**：重活给便宜/快的 Cline，主脑不读整库。
- **Lobster**：复杂多步流程用确定性管道，少来回 tool 调用。
- 缓存：此端点不可用（实测）。

## 三个「联想」skill（Ready + 可见）
- `cline-coding` → 提代码/多文件/调试
- `wechat` → 提微信/群消息/朋友圈
- `lobster` → 复杂多步/审批流/批处理
