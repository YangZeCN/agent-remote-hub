# OpenCode Telegram Bot 调研

> 调研日期：2026-07-22  
> 仓库数据是调研快照，会随社区活动变化。

## 决策摘要

推荐把 [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot) 作为 OpenCode + Telegram 的首选 PoC。它不是简单通知插件，而是独立运行的移动客户端和 OpenCode supervisor，能够管理项目、session、worktree、权限、问题、定时任务以及本地 OpenCode 进程。

它的社区规模、发布频率、测试覆盖和 Windows 支持明显领先同类项目。当前不建议直接替换飞书生产路径，而应先并行运行 3 至 7 天，验证网络稳定性、会话接管和长任务行为。

## 主候选评估

### 项目活跃度快照

| 指标 | 2026-07-22 快照 |
|---|---:|
| Stars | 949 |
| Forks | 166 |
| Open issues | 28（其中 GitHub 统计可能包含 PR） |
| 最新版本 | `v0.22.3` |
| 测试文件 | 124 |
| 测试代码体积 | 约 950 KB |
| License | MIT |

近期版本持续发布，主分支 CI 执行 ESLint、TypeScript build 和 Vitest，调研时最新运行全部通过。npm 包 `@grinev/opencode-telegram-bot@0.22.3` 已在 Windows 上完成 CLI 冒烟测试。

### 架构

```text
Telegram 客户端
       |
       v
Telegram Bot API
       ^  长轮询，无入站端口
       |
opencode-telegram-bot
       |
       v  HTTP API + SSE
OpenCode Server（默认 localhost:4096）
       |
       v
模型供应商 API
```

Bot 使用 grammY 长轮询，正常模式不需要 webhook、公网 IP 或入站端口。它通过官方 OpenCode SDK 和 SSE 连接本地 OpenCode Server。

### 主要能力

- 项目、session 和 worktree 浏览与切换。
- 跟踪并继续本地 OpenCode CLI session。
- 启动、停止、健康检查和自动重启 OpenCode Server。
- 流式回复、工具调用摘要、diff、文件和附件处理。
- 在 Telegram 内回答 Agent 问题和审批权限。
- 模型、Agent、variant 和 context 控制。
- 定时任务及后台 session 通知。
- 中文等多语言 UI。
- 使用 `TELEGRAM_ALLOWED_USER_ID` 限制单一授权用户。

这套能力与本仓库希望采用的“通道桥接独立于 Agent 进程，并能监督 Agent 生命周期”方向一致。

## 已知限制和风险

### 产品边界

- 主要面向单用户、单一主要聊天上下文。
- 可以切换项目和 session，但不原生支持每个 Telegram Forum Topic 对应独立并发 session。
- Bot 离线期间无法可靠展示离线状态或处理用户侧积压的业务确认。

### 当前 backlog 中与本场景相关的项目

- 消息排队功能尚未完成。
- 定时任务通知可能污染当前 active session。
- 部分长消息和 task detail 仍受 Telegram 4096 字节限制。
- 本地模型选择体验仍在规划。

### 供应链和运行时

- 要求 Node.js 20 或更高版本。
- 使用 `better-sqlite3` 原生依赖；当前 Windows npm 冒烟测试通过，但升级 Node.js 时仍应重新验证预编译包兼容性。
- 安装时观察到部分间接依赖弃用告警，包括 `glob@10.5.0`；PoC 可继续，长期部署应跟踪上游更新。

### 数据边界

普通 Telegram Bot 私聊不是端到端加密。Prompt、回复、源码片段、diff 和上传附件会经过 Telegram 基础设施。高度敏感的私有代码需要单独进行合规评估。

## 网络要求

运行 Bot 的机器不必物理位于境外，但必须具有稳定访问 Telegram Bot API 的网络路径。

网络连接相互独立：

1. 手机到 Telegram：手机需要能够使用 Telegram。
2. Bot 主机到 Telegram：Bot 需要访问 Bot API 并下载 Telegram 文件。
3. Bot 到 OpenCode：默认访问 `http://localhost:4096`，可保持纯本地。
4. OpenCode 到模型 API：由 OpenCode 自己访问模型供应商，不经过 Telegram 代理。
5. 可选 STT、TTS 和文档提取 API：各自需要独立网络可达性。

### 方案 A：本机正向代理

适合电脑已有 Clash、Mihomo 或企业代理的情况：

```env
TELEGRAM_PROXY_URL=socks5://127.0.0.1:7890
```

支持 SOCKS5 和 HTTP/HTTPS 代理。该配置覆盖 Telegram Bot API 请求和 Telegram 文件下载。

### 方案 B：自建 HTTPS 反向代理

适合不希望 Windows 主机依赖本地代理客户端的情况：

```env
TELEGRAM_API_ROOT=https://tg-proxy.example.com
TELEGRAM_PROXY_SECRET=使用足够长的随机值
```

反向代理必须部署在能够访问 `api.telegram.org` 的网络中。它能看到 URL 中的 Bot Token，因此应由自己控制、强制 HTTPS、关闭含 Token 的访问日志，并校验 `X-Proxy-Secret`。

`TELEGRAM_PROXY_URL` 与 `TELEGRAM_API_ROOT` 是互斥模式，不能同时配置。

### 方案 C：仅强制 IPv4

```env
TELEGRAM_FORCE_IPV4=true
```

该选项只处理 IPv6 路由异常，不会绕过网络封锁，不能替代代理。

### 端口安全

Telegram 使用长轮询，不需要把 OpenCode 暴露到公网。建议：

- OpenCode 仅监听 `127.0.0.1`。
- 不开放 4096 或随机 OpenCode 端口的公网入站。
- `.env` 中的 Bot Token 和代理 Secret 不提交到 Git。

## 同类方案对比

| 项目 | 快照 | 适用场景 | 判断 |
|---|---|---|---|
| `grinev/opencode-telegram-bot` | 949 stars，持续发布 | 单用户完整远控 | 首选 |
| `shanekunz/opencode-telegram-group-topics-bot` | 12 stars，落后上游 188 commits | Forum Topics 并发 session | 有明确 Topics 需求时再评估 |
| `Tommertom/opencode-telegram` | 44 stars，近期代码活动较少 | 较轻量桥接 | 成熟度不足以替代首选 |
| `gabriel-trigo/opencode-telegram-bridge` | 14 stars，偏 Linux/systemd | 轻量 Linux 部署 | Windows 场景不优先 |
| `artickc/opencode-telegram-bot` | 7 stars，项目较新 | HTTP/SSE 远控 | 继续观察 |

Topics fork 已与上游显著分叉：调研时领先 77 commits、落后 188 commits、涉及 211 个变化文件，最新发布停在 `v0.17.0`。它提供有价值的并发模型，但继承新修复的成本较高。

## 与当前飞书通道比较

| 维度 | `opencode-lark` | `grinev/opencode-telegram-bot` |
|---|---|---|
| 国内网络 | 通常可直连 | 手机和 Bot 主机通常都需要代理 |
| 入站端口 | 不需要 | 不需要 |
| 移动端命令体验 | 飞书无原生斜杠命令菜单 | Telegram 原生命令和 inline button |
| 项目/worktree 切换 | 依赖 bridge 能力和外围脚本 | 原生支持 |
| OpenCode 生命周期管理 | 当前由本仓库 PowerShell 脚本负责 | Bot 内置 start/stop/monitor/restart |
| 并发会话模型 | 多个飞书 chat 可映射不同 session | 主项目偏单一聊天上下文 |
| 已知可靠性风险 | 存在延迟 ACK 与去重窗口问题 | 未发现同类已确认重放问题，仍需 PoC |
| 数据经过平台 | 飞书 | Telegram |

## PoC 计划和通过标准

建议飞书与 Telegram 并行运行，不立即迁移现有生产会话。

### 测试范围

1. 选择一个非关键测试项目，不授权生产凭证。
2. 连续执行多轮 30 分钟以上的任务，检查回复完整性和重复提交。
3. 在 Telegram 中审批权限、回答问题并中止任务。
4. 从 TUI 切换到 Telegram 继续已有 session，再切回本地。
5. 验证项目、session 和 worktree 切换不会串目录。
6. 分别重启 Bot 和 OpenCode，检查 session 与定时任务恢复。
7. 断开并恢复代理，观察长轮询重连和消息行为。
8. 测试长文本、图片、普通文件和中文 Markdown。
9. 检查日志和持久化目录中是否泄露 Token。

### 通过标准

- 不出现同一用户消息被重复提交。
- 代理恢复后 Bot 无需人工重建 session。
- 所有高风险权限请求都能在手机端明确确认或拒绝。
- OpenCode 继续只监听本机地址。
- 项目切换、TUI 接管和 Windows 重启恢复符合预期。

## 建议决策

- 需要国内直连和多飞书群聊隔离：暂时保留飞书，同时推动可靠性修复。
- 需要成熟的手机远控、项目切换和 supervisor：优先验证 `grinev/opencode-telegram-bot`。
- 明确需要 Telegram Topics 并行任务：单独验证 topics fork，不要假设它能持续同步上游修复。
- 涉及高度敏感源码且不能经过第三方消息平台：飞书和 Telegram 都不是理想传输边界，应改用自托管客户端或受控 VPN。

## 参考链接

- [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot)
- [shanekunz/opencode-telegram-group-topics-bot](https://github.com/shanekunz/opencode-telegram-group-topics-bot)
- [飞书通道可靠性记录](feishu-reliability.md)