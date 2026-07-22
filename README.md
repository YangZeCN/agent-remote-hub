# Agent Remote Hub

远程控制 AI 编程助手的统一方案集合，支持多种 AI Agent 和多种通信通道。

## 架构概览

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
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

核心设计：Agent 和通道解耦，通过桥接服务连接。详见 [整体架构设计](docs/architecture.md)。

## 方案矩阵

| | 飞书（Feishu） | Telegram |
|---|---|---|
| **OpenCode** | ⚠️ [可用，存在重放风险](agents/opencode/feishu/) | 🧪 [已调研，待 PoC](docs/telegram-bot-research.md) |
| **VSCode** | 🔜 规划中 | 🔜 规划中 |

## 快速开始

### 1. 选择方案

根据上方矩阵选择你要使用的 Agent + 通道组合，进入对应目录查看详细说明。

当前可用方案：

| 方案 | 入口 | 说明 |
|---|---|---|
| OpenCode + 飞书 | [agents/opencode/feishu/](agents/opencode/feishu/) | 已落地；使用前阅读[可靠性记录](docs/feishu-reliability.md) |
| OpenCode + Telegram | [调研报告](docs/telegram-bot-research.md) | 推荐 `grinev/opencode-telegram-bot` 进入 PoC，尚未在本仓库落地 |

### 2. 环境配置

所有方案共享一套基础环境，通道相关的依赖在各自文档中说明。

→ [环境配置指南](agents/opencode/docs/setup.md)

### 3. 启动

以 OpenCode + 飞书为例：

```powershell
cd agents/opencode/feishu
.\start-opencode-remote.ps1
```

各方案的启动方式请参考对应的通道文档。

## 项目结构

```
agent-remote-hub/
├── docs/                          # 通用文档
│   ├── architecture.md            # 整体架构设计
│   ├── comparison.md              # 方案对比分析
│   ├── feishu-reliability.md      # 飞书消息重放与修复建议
│   ├── feishu-setup.md            # 飞书应用创建指南
│   └── telegram-bot-research.md   # OpenCode Telegram Bot 调研
│
├── agents/                        # 按 AI Agent 分类
│   ├── opencode/                  # OpenCode 方案
│   │   ├── README.md              # OpenCode 方案总览
│   │   ├── feishu/                # 飞书通道
│   │   │   ├── start-opencode-remote.ps1
│   │   │   └── README.md
│   │   └── docs/
│   │       └── setup.md           # 环境配置
│   │
│   └── vscode/                    # VSCode 方案（规划中）
│       ├── feishu/
│       └── telegram/
```

## 文档导航

| 文档 | 说明 |
|---|---|
| [整体架构](docs/architecture.md) | 系统架构设计、设计原则和技术选型 |
| [方案对比](docs/comparison.md) | 不同远程控制方案的对比分析 |
| [飞书配置指南](docs/feishu-setup.md) | 如何创建和配置飞书应用 |
| [飞书可靠性记录](docs/feishu-reliability.md) | 消息重放问题、根因和修复建议 |
| [Telegram Bot 调研](docs/telegram-bot-research.md) | 候选项目、网络要求和 PoC 建议 |
| [环境配置](agents/opencode/docs/setup.md) | 从零搭建运行环境 |

## License

MIT
