# Agent Remote Hub

远程控制 AI 编程助手的统一方案集合，支持多种 AI Agent 和多种通信通道。

## 支持的 Agent

- **OpenCode** - 终端 AI 编程助手，支持远程控制和会话持久化
- **VSCode** - （规划中）VSCode 扩展远程控制方案

## 支持的通道

- **飞书（Feishu）** - 企业级即时通讯，支持消息推送和会话管理
- **Telegram** - （规划中）个人即时通讯通道

## 快速开始

根据你的需求选择对应的方案：

### OpenCode + 飞书

```bash
cd agents/opencode/feishu
./start-opencode-remote.ps1
```

详细配置请参考：
- [OpenCode 方案说明](agents/opencode/README.md)
- [飞书通道配置](agents/opencode/feishu/README.md)
- [环境配置指南](agents/opencode/docs/setup.md)

## 项目结构

```
agent-remote-hub/
├── docs/                          # 通用文档
│   ├── architecture.md            # 整体架构设计
│   ├── comparison.md              # 方案对比分析
│   └── feishu-setup.md            # 飞书应用创建指南
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

- [整体架构](docs/architecture.md) - 系统架构设计和技术选型
- [方案对比](docs/comparison.md) - 不同远程控制方案的对比分析
- [飞书配置指南](docs/feishu-setup.md) - 如何创建和配置飞书应用

## License

MIT
