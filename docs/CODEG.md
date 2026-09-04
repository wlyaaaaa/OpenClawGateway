# CodeG / Cline 通过 MCP 接入 OpenClaw

## 当前可行路线

```text
CodeG 中的 Cline
    ↓ stdio MCP
openclaw-bridge
    ↓ 本机 Gateway
OpenClaw 会话与渠道工具
```

本仓库不把 CodeG 的 OpenClaw ACP（智能体通信协议）直连写成可用能力：既有握手与 per-session MCP（逐会话模型上下文协议）组合不兼容。当前公开路线是 Cline 通过 `openclaw mcp serve` 或 PCConfig 受控启动器连接 Gateway。

## 配置

```powershell
pwsh -NoProfile -File .\tools\setup-codeg-bridge.ps1
```

脚本会：

1. 要求 PCConfig 受控启动器，使 Cline 配置不保存 Gateway 密码；缺少该入口时先失败，不降级成明文配置；
2. 解析现有 Cline MCP JSON，保留未知根键和其他 `mcpServers`；
3. 只 upsert（插入或更新）`mcpServers.openclaw-bridge`；
4. 写入前保留一份稳定恢复备份，使用同目录临时文件原子替换；
5. 写后重新解析并核对其他服务未丢失；相同结果重复运行时不改字节。

畸形 JSON 会在备份和写入之前失败，原文件字节保持不变。

## 配置后的用户动作

1. 在 CodeG 的 MCP 页面刷新；
2. 将 `openclaw-bridge` 启用给 Cline；
3. 让 Cline 初始化 MCP；
4. 回读工具列表后，再做一次不含私人内容的只读工具调用。

公开脚本目前描述的工具轴包括：会话列表与读取、消息读取与发送、事件轮询与等待、附件获取、待处理权限列表与响应。实际可用数量和名称必须以真实 `tools/list` 为准。

## 验收边界

`test-codeg-bridge.ps1` 已用隔离夹具验证：

- 保留其他 MCP Server 和未知根键；
- 重复运行幂等；
- 畸形输入不改原文件；
- UTF-8 无 BOM；
- 受控启动器缺失时原文件字节不变；
- Windows PowerShell 5.1 与 PowerShell 7 解析。

这些测试没有启动真实 MCP 常驻进程，也没有证明 Cline 刷新、受控启动器认证、`initialize`、`tools/list` 或消息发送成功。端口在线只能证明 Gateway 可达，不能替代 MCP 握手。
