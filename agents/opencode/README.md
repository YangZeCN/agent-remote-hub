# OpenCode 远程控制方案

OpenCode 是一个终端 AI 编程助手，通过 HTTP API 提供对话能力。本方案实现了对 OpenCode 的远程控制和会话管理。

## 架构概览

```
┌─────────────────┐
│  通信通道客户端  │  ← 飞书 / Telegram / ...
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  桥接服务        │  ← 通道 ↔ OpenCode 桥接
│  (通道相关连接)  │     如 opencode-lark (本地 3001)
└──────┬──────────┘
       │ HTTP API + SSE
       ▼
┌─────────────────┐
│  opencode serve │  ← AI 引擎（随机端口）
└──────┬──────────┘
       │ HTTP API + SSE
       ▼
┌─────────────────┐
│  opencode TUI   │  ← 本地终端界面（可选）
└─────────────────┘
```

核心思路：通道桥接服务连接通信平台和 OpenCode HTTP API，本地 TUI 可通过 `attach` 模式共享同一会话上下文。

## 核心组件

- **opencode serve**: OpenCode 的 HTTP 服务端，提供 AI 对话能力（随机端口）
- **通道桥接服务**: 将通信平台的消息转发给 OpenCode（如 `opencode-lark` 用于飞书）
- **opencode TUI**: 本地终端界面，可通过 `attach` 模式与通道共享同一会话上下文

## 支持的通道

| 通道 | 状态 | 文档 |
|---|---|---|
| 飞书（Feishu） | ⚠️ 可用，存在消息重放风险 | [使用文档](feishu/) · [可靠性记录](../../docs/feishu-reliability.md) |
| Telegram | 🧪 已完成调研，待 PoC | [调研报告](../../docs/telegram-bot-research.md) |

## 会话管理

### 会话持久化

- **对话历史**: 当前存储在 `~/.local/share/opencode/opencode.db`，独立于 serve 进程
- **通道映射**: 各通道的桥接服务维护"通道会话 ↔ OpenCode session"的对应关系
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

### 数据目录隔离

OpenCode 的 session 按工作目录隔离。为了避免不同项目之间的会话冲突，桥接服务的数据目录会根据工作目录的哈希值进行隔离：

```
~/.config/opencode-<channel>/<hash>/data/
```

例如飞书通道为 `~/.config/opencode-lark/<hash>/data/`。

其中 `<hash>` 是工作目录路径的 SHA256 哈希值（前 16 位）。这样：
- 同一项目目录始终复用同一份数据
- 不同项目目录互不干扰
- 切换项目时不会丢失历史会话映射

## 快速开始

选择你要使用的通道：

### 飞书（Feishu）

```bash
cd feishu
./start-opencode-remote.ps1
```

详细配置请参考 [飞书通道文档](feishu/README.md)。

### Telegram

当前尚未在本仓库提供启动脚本。候选实现、网络要求和验证计划见 [OpenCode Telegram Bot 调研](../../docs/telegram-bot-research.md)。

## 环境配置

首次使用需要安装相关依赖。环境配置分为两部分：

1. **通用依赖**（所有通道共享）：Node.js、Bun、opencode
2. **通道专属配置**：各通道有自己的桥接工具和凭证要求

→ [环境配置指南](docs/setup.md)

## 相关链接

- [OpenCode 官方文档](https://github.com/opencode-ai/opencode)
- [opencode-lark 项目](https://github.com/guazi04/opencode-lark)
- [飞书通道可靠性记录](../../docs/feishu-reliability.md)
- [OpenCode Telegram Bot 调研](../../docs/telegram-bot-research.md)
