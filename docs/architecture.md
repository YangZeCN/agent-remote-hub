# 整体架构设计

本文档描述 Agent Remote Hub 的整体架构设计和技术选型。

## 设计目标

1. **多 Agent 支持**：支持 OpenCode、VSCode 等不同的 AI 编程助手
2. **多通道支持**：支持飞书、Telegram 等不同的通信通道
3. **会话隔离**：不同项目、不同通道的会话互不干扰
4. **易于扩展**：新增 Agent 或通道时，只需添加对应目录和脚本

## 架构层次

```
┌─────────────────────────────────────────────────┐
│              用户层（User Layer）                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ 飞书客户端│  │ Telegram │  │  其他通道 │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
└───────┼──────────────┼──────────────┼───────────┘
        │              │              │
        ▼              ▼              ▼
┌─────────────────────────────────────────────────┐
│            通道层（Channel Layer）                │
│  ┌──────────────────────────────────────────┐  │
│  │  桥接服务（Bridge Service）               │  │
│  │  - opencode-lark（飞书）                 │  │
│  │  - opencode-telegram（Telegram）         │  │
│  │  - 其他通道桥接                          │  │
│  └──────────────┬───────────────────────────┘  │
└─────────────────┼───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│            Agent 层（Agent Layer）                │
│  ┌──────────────────────────────────────────┐  │
│  │  AI 引擎服务（AI Engine Service）         │  │
│  │  - opencode serve（OpenCode）            │  │
│  │  - VSCode Extension Host（VSCode）       │  │
│  │  - 其他 Agent 服务                       │  │
│  └──────────────┬───────────────────────────┘  │
└─────────────────┼───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│            存储层（Storage Layer）                │
│  ┌──────────────────────────────────────────┐  │
│  │  会话存储                                 │  │
│  │  - OpenCode: ~/.local/share/opencode/    │  │
│  │  - 通道映射: 各通道独立维护              │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## 核心设计原则

### 1. 通道优先组织

每个 Agent 下按通道组织脚本和文档：

```
agents/
├── opencode/
│   ├── feishu/          # 飞书通道
│   ├── telegram/        # Telegram 通道
│   └── docs/            # 通用文档
└── vscode/
    ├── feishu/
    └── telegram/
```

**理由**：
- 不同通道的桥接工具完全不同（启动参数、端口、配置）
- 用户视角清晰：先选 Agent，再选通道
- 扩展方便：新增通道只需在对应 Agent 下添加目录

### 2. 会话隔离策略

#### 项目级隔离

OpenCode 的 session 按工作目录（cwd）隔离。不同项目的会话互不干扰。

#### 通道级隔离

每个通道的桥接服务维护独立的映射数据库，具体实现因通道而异：

**OpenCode + 飞书（opencode-lark）**：
```
~/.config/opencode-lark/<hash>/data/sessions.db
```
其中 `<hash>` 是工作目录路径的 SHA256 哈希值（前 16 位）。

**OpenCode + Telegram（grinev/opencode-telegram-bot）**：
```
~/.config/opencode-telegram-bot/settings.json
```
使用 JSON 配置文件存储项目、会话和设置。

**隔离效果**：
- 同一项目 + 同一通道 = 复用同一份数据
- 不同项目 = 隔离的数据目录或配置
- 切换项目时不会丢失历史会话映射

### 3. 端口管理策略

#### 随机端口（推荐）

AI 引擎服务（如 `opencode serve`）使用随机端口：
- 避免端口冲突
- 系统自动分配，几乎不会失败
- 脚本自动检测并连接

#### 通道相关的桥接连接

桥接服务的连接方式由通道实现决定：

- 当前 `opencode-lark` 在本机使用固定端口 3001，同一时刻只运行一个实例，启动脚本会识别并清理旧实例。
- `grinev/opencode-telegram-bot` 使用 Telegram 长轮询，不需要 webhook 或公网入站端口；默认从本机连接 `localhost:4096` 的 OpenCode Server。
- 固定端口不是所有 bridge 的共同要求。无论采用哪种通道，OpenCode API 都应优先只监听本机地址。

### 4. 进程管理策略

#### 启动脚本职责

一键启动脚本负责：
1. 启动或复用 AI 引擎服务
2. 启动桥接服务
3. 启动本地 TUI（可选）
4. 监控进程状态
5. 退出时清理资源

#### 清理策略

- **Ctrl+C 退出**：干净退出，停止本脚本启动的所有进程
- **窗口关闭**：可能残留进程，但下次运行时会自动清理
- **幂等性**：脚本可以反复运行，不会造成重复启动

## 技术选型

### PowerShell 脚本

**选择理由**：
- Windows 原生支持，无需额外依赖
- 强大的进程管理能力
- 易于与 Windows 系统集成

**替代方案**：
- Bash 脚本（Linux/macOS）
- Python 脚本（跨平台，但需要 Python 环境）

### SQLite 数据库

**选择理由**：
- 轻量级，无需独立数据库服务
- 单文件存储，易于备份和迁移
- 支持 WAL 模式，并发性能好

**使用场景**：
- 通道映射数据库（sessions.db）
- 记忆存储（memory.db）

### 通道实时通信

**选择理由**：
- 支持实时或准实时双向通信
- 飞书 bridge 使用 WebSocket 事件订阅；Telegram 候选实现使用 Bot API 长轮询和 OpenCode SSE
- 低延迟，适合交互式场景

## 扩展指南

### 新增通道

1. 在对应 Agent 下创建通道目录：
   ```
   agents/opencode/telegram/
   ```

2. 添加启动脚本：
   ```
   agents/opencode/telegram/start-opencode-remote.ps1
   ```

3. 添加通道文档：
   ```
   agents/opencode/telegram/README.md
   ```

4. 更新 Agent 总览文档，添加新通道链接

### 新增 Agent

1. 创建 Agent 目录：
   ```
   agents/cursor/
   ```

2. 添加 Agent 总览文档：
   ```
   agents/cursor/README.md
   ```

3. 按通道组织脚本和文档：
   ```
   agents/cursor/feishu/
   agents/cursor/telegram/
   ```

4. 更新根 README，添加新 Agent 链接

## 故障排查

各通道的具体故障排查请参考对应的通道文档：

- [飞书通道故障排查](../agents/opencode/feishu/README.md#常见问题)
- [飞书通道可靠性记录](feishu-reliability.md)
- [Telegram Bot 调研](telegram-bot-research.md)

### 通用排查思路

1. **端口冲突**：检查是否有旧实例未清理
2. **会话分裂**：检查数据目录是否发生变化
3. **进程残留**：手动清理或重启脚本

## 相关链接

- [方案对比](comparison.md)
- [飞书配置指南](feishu-setup.md)
- [飞书通道可靠性记录](feishu-reliability.md)
- [OpenCode Telegram Bot 调研](telegram-bot-research.md)
