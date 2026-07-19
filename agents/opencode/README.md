# OpenCode 远程控制方案

OpenCode 是一个终端 AI 编程助手，通过 HTTP API 提供对话能力。本方案实现了对 OpenCode 的远程控制和会话管理。

## 架构概览

```
┌─────────────┐
│  飞书客户端  │  ← 手机/电脑
└──────┬──────┘
       │ WebSocket
       ▼
┌─────────────────────┐
│  飞书开放平台        │  ← 消息路由
└──────┬──────────────┘
       │ WebSocket
       ▼
┌─────────────────────┐
│  opencode-lark      │  ← 飞书 ↔ OpenCode 桥接
│  (端口 3001)        │
└──────┬──────────────┘
       │ HTTP API + SSE
       ▼
┌─────────────────────┐
│  opencode serve     │  ← AI 引擎（随机端口）
└──────┬──────────────┘
       │ stdin/stdout
       ▼
┌─────────────────────┐
│  opencode TUI       │  ← 本地终端界面（可选）
└─────────────────────┘
```

## 核心组件

- **opencode-lark**: 飞书消息桥接服务，监听飞书事件并转发给 OpenCode
- **opencode serve**: OpenCode 的 HTTP 服务端，提供 AI 对话能力
- **opencode TUI**: 本地终端界面，可与飞书共享同一会话上下文

## 支持的通道

- [飞书（Feishu）](feishu/) - 企业级即时通讯集成

## 会话管理

### 会话持久化

- **对话历史**: 存储在 `~/.local/share/opencode/storage/`，独立于 serve 进程
- **通道映射**: 各通道的桥接服务维护"通道会话 ↔ OpenCode session"的对应关系
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

### 数据目录隔离

OpenCode 的 session 按工作目录隔离。为了避免不同项目之间的会话冲突，桥接服务的数据目录会根据工作目录的哈希值进行隔离：

```
~/.config/opencode-lark/<hash>/data/
```

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

## 环境配置

首次使用需要安装相关依赖，请参考 [环境配置指南](docs/setup.md)。

## 相关链接

- [OpenCode 官方文档](https://github.com/opencode-ai/opencode)
- [opencode-lark 项目](https://github.com/guazi04/opencode-lark)
