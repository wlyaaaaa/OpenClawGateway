---
name: cline-coding
description: "Use whenever the user asks to write / edit / refactor / debug code, make multi-file changes, build a feature, fix a bug, or run a coding project — delegate to the local Cline CLI (cheap model, diffs-only) to save tokens. NOT for single-line edits or read-only code lookup (do those yourself)."
metadata:
  openclaw:
    emoji: "🦞"
    requires:
      anyBins: ["cline"]
      config: ["skills.entries.cline-coding.enabled"]
---

# 委托 Cline 编码（省 token）

多文件编码 / 调试 / 构建功能 / 修 bug 这类**重活**，**不要自己逐行读写代码**（用我这个贵模型读整库会烧大量 token），委托本机 Cline：

```bash
cline -c "<目标仓库绝对路径>" "<一句话任务>"
```

- Cline 默认 act 模式 + 自动批准、diffs-only，用配置的默认模型干重活。
- 我（主脑 qwen3.7-max）**只下达任务、读回摘要、向用户汇报**，不把整个代码库读进上下文 —— 这是省 token 的关键。
- Cline 全局规范在 `~/Documents/Cline/Rules/`，无需重复交代；需结构化结果加 `--json`，需超时加 `-t 600`。

## 决策边界
- **单行小改 / 只读看代码**：我自己用 exec 直接做，别起 Cline。
- **多文件工程 / 反复调试 / 浏览器自动化以外的编码**：委托 Cline。
