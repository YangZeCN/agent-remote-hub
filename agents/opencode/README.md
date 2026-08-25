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
| Telegram | ✅ 可用 | [使用文档](telegram/) · [调研报告](../../docs/telegram-bot-research.md) |

## 通道对比

| 维度 | 飞书 (`opencode-lark`) | Telegram (`opencode-telegram-bot`) |
|---|---|---|
| 运行时 | Bun | Node.js |
| 入站端口 | 3001（固定） | 不需要（长轮询） |
| 消息接收 | ⚠️ ACK 被业务处理阻塞，存在重放风险 | 长轮询，当前无已确认的同类重放问题 |
| 业务幂等 | ⚠️ 60 秒 TTL，延迟重放可绕过 | 仍需应用侧保证并通过 PoC 验证 |
| 移动端命令 | 无原生斜杠命令 | 原生命令 + inline button |
| 项目切换 | 依赖外围脚本 | 原生支持 |
| OpenCode 生命周期 | 靠 PowerShell 脚本 | Bot 内置 start/stop/monitor |
| 网络要求 | 国内直连 | 需要访问 Telegram API |
| 数据经过平台 | 飞书 | Telegram |

### 多通道并行架构

本仓库设计支持多通道并行。不同通道使用不同的运行时、配置目录和网络协议，可以同时运行，互不干扰：

```
┌──────────────┐     ┌──────────────┐
│  飞书客户端   │     │ Telegram 客户端│
└─────────────┘     └─────────────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│ opencode-lark│     │opencode-     │
│ (Bun, :3001) │     │telegram      │
│              │     │(Node.js)     │
└──────┬───────┘     └──────┬───────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│ serve (端口A) │     │ serve (端口B) │
│ (项目X)      │     │ (项目Y)      │
└──────────────┘     └──────────────┘
```

**隔离策略**：
- Telegram 启动脚本始终创建独立的 `opencode serve`
- 飞书和 Telegram 可以指向同一项目目录，但不会复用同一个 serve 进程
- 两个通道的聊天到 OpenCode session 映射仍各自维护

### 选型建议

| 场景 | 建议 |
|---|---|
| 需要国内直连 + 多群聊隔离 | 保留飞书，推动上游修复 |
| 需要成熟的手机远控 + 项目切换 | 优先验证 Telegram |
| 不可逆操作多、需要可靠性 | Telegram 更合适（无已知重放问题） |
| 高度敏感源码 | 两者都不是理想传输边界，应改用自托管客户端或受控 VPN |

## 会话管理

### 会话持久化

- **对话历史**: 当前存储在 `~/.local/share/opencode/opencode.db`，独立于 serve 进程
- **通道映射**: 各通道的桥接服务维护"通道会话 ↔ OpenCode session"的对应关系
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

### 数据目录隔离

OpenCode 的 session 按工作目录隔离。通道自身的配置和映射采用不同策略：

- 飞书：`~/.config/opencode-lark/<hash>/data/`，其中 `<hash>` 是工作目录路径 SHA256 的前 16 位
- Telegram：Windows 下使用 `%APPDATA%\opencode-telegram-bot\` 保存全局配置；启动脚本通过独立 serve 的 cwd 和 `OPENCODE_API_URL` 选择当前项目

两个通道不会共用映射数据库。Telegram 启动脚本也不会复用飞书的 serve 进程。

## 快速开始

选择你要使用的通道：

### 飞书（Feishu）

```bash
cd feishu
./start-opencode-remote.ps1
```

详细配置请参考 [飞书通道文档](feishu/README.md)。

### Telegram

```bash
cd telegram
./start-opencode-remote.ps1
```

详细配置请参考 [Telegram 通道文档](telegram/README.md)。首次使用需要配置代理访问 Telegram API，详见文档中的[网络配置](telegram/README.md#网络配置)章节。

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
