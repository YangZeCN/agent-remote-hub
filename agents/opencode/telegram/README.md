# OpenCode + Telegram 通道

通过 Telegram 远程操控 OpenCode AI 助手，实现手机端随时随地的代码协作。

> **可靠性**：当前尚未观察到类似飞书通道的延迟重放问题。Bot 使用长轮询接收消息，但 Telegram Bot API 不替代业务幂等；正式迁移前仍应按本文的 PoC 计划验证长任务、断网重连和高风险操作。

## 架构原理

```
┌─────────────┐
│ Telegram 客户端 │  ← 手机/电脑
└──────┬──────┘
   │ Telegram Bot API（长轮询）
       ▼
┌─────────────────────┐
│  opencode-telegram  │  ← Telegram ↔ OpenCode 桥接
│  (Node.js 进程)     │     无需入站端口
└─────┬───────────────┘
       │ HTTP API + SSE
       ▼
┌─────────────────────┐
│  opencode serve     │  ← AI 引擎（随机端口）
└──────┬──────────────┘
   │ HTTP API + SSE
       ▼
┌─────────────────────┐
│  opencode TUI       │  ← 本地终端界面（可选）
└─────────────────────┘
```

### 核心组件

- **opencode-telegram-bot**: Telegram 消息桥接服务，使用 grammY 长轮询接收消息并转发给 OpenCode
- **opencode serve**: OpenCode 的 HTTP 服务端，提供 AI 对话能力
- **opencode TUI**: 本地终端界面，可与 Telegram 共享同一会话上下文



### 会话持久化

- **对话历史**: 存储在 `~/.local/share/opencode/opencode.db`，独立于 serve 进程
- **Bot 配置**: `%APPDATA%\opencode-telegram-bot\.env` 和 `settings.json`
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

## 快速开始

### 前置条件

- Node.js 22 或更高版本
- `opencode-ai` 和 `@grinev/opencode-telegram-bot`
- 已创建的 Telegram Bot（通过 @BotFather）
- 你的 Telegram User ID（通过 @userinfobot 获取）
- 能够访问 Telegram Bot API 的网络环境

### 一键启动

```powershell
.\start-opencode-remote.ps1
```

默认行为会启动本地 OpenCode TUI，并自动 attach 到 Telegram bot 的 session，实现手机和电脑端消息同步。

**TUI 会自动跟随 session 切换**：当你在 Telegram 中切换到其他 session 时，本地 TUI 会自动重启并 attach 到新的 session，始终保持同步。

**TUI 窗口自动关闭**：脚本会在 Windows Terminal 的 `settings.json` 中幂等地添加一个隐藏 profile（`opencode-remote-tui`，`closeOnExit=always`），确保切换 session 或 Ctrl+C 退出时，旧的 TUI 窗口自动关闭，不会残留。该 profile 只影响本脚本启动的 TUI，不影响你其他终端窗口。

如果只想运行 Telegram bot（不拉起本地 TUI），可使用：

```powershell
.\start-opencode-remote.ps1 -NoTui
```

脚本会自动：
1. 检查 OpenCode、Telegram Bot 配置
2. **自动清理**本机残留的 opencode-telegram 进程（若检测到已有实例，会先停止再继续启动）
3. 启动 Telegram 专用的 `opencode serve`（随机端口，不复用飞书 serve）
4. 自动发现 serve 监听的端口
5. 验证 Telegram Bot 配置（Token、User ID）
6. 显示 Telegram 网络模式（直连、代理或反向代理）
7. 启动 opencode-telegram 并连接到该端口
8. 等待 bot 创建/恢复 session，然后启动 TUI 并 attach 到该 session
9. 监控 session 切换，自动重启 TUI 跟随新 session
10. **保持运行**，脚本窗口会一直阻塞，直到你按 Ctrl+C 或 bot 退出
11. 退出时（Ctrl+C）自动清理本脚本启动的 serve、bot 和 TUI 进程

#### 指定项目目录

```powershell
.\start-opencode-remote.ps1 -WorkingDir "C:\Projects\MyApp"
```

脚本始终启动独立 serve。即使飞书正在操作同一个项目目录，两个通道也会使用不同端口和不同进程。

### 首次配置

#### 第一步：创建 Telegram Bot，获取 Token

1. 在 Telegram 中搜索并打开 **[@BotFather](https://t.me/BotFather)**
2. 发送 `/newbot`
3. 按提示输入机器人名称（显示名，如 `My OpenCode Bot`）
4. 按提示输入用户名（必须以 `bot` 结尾，如 `myopencode_bot`）
5. BotFather 回复一串 `123456789:AAXXXXXXXXXXXXXXX` 格式的字符串，即 **Bot Token**

> Bot Token 是敏感凭证，不要提交到 Git 或分享给他人。

#### 第二步：获取你的 Telegram User ID

1. 在 Telegram 中搜索并打开 **[@userinfobot](https://t.me/userinfobot)**
2. 发送任意消息（如 `/start`）
3. Bot 会回复你的账号信息，其中 `Id: 7192800053` 格式的数字即为你的 **User ID**

> User ID 是限制 Bot 只响应你本人消息的安全设置。

#### 第三步：运行交互式配置

```powershell
opencode-telegram config
```

各项配置含义：
- **语言** — 默认英文，可选中文（输入 `7`），两者均可正常使用
- **Bot Token** — 第一步获取的 Token
- **Telegram User ID** — 第二步获取的数字 ID
- **OpenCode API URL** — 直接回车跳过（启动脚本会自动覆盖为正确端口）
- **用户名 / 密码** — 直接回车跳过

配置保存在 `%APPDATA%\opencode-telegram-bot\.env`（即 `C:\Users\<你的用户名>\AppData\Roaming\opencode-telegram-bot\.env`）。

#### 第四步：配置模型（手动）

`opencode-telegram config` 命令不会询问模型配置，需要手动编辑 `.env` 文件：

```env
# 编辑 %APPDATA%\opencode-telegram-bot\.env
OPENCODE_MODEL_PROVIDER=new-api
OPENCODE_MODEL_ID=qwen3.7-plus
```

> **注意**：Telegram bot 的模型配置独立于本地 OpenCode TUI。如果 bot 返回空消息或无响应，请检查 `.env` 中的模型配置是否正确，并确保该模型在 OpenCode 中可用。

## 常见问题

### Q: 为什么用随机端口而不是固定端口？

**A**: 避免端口冲突。固定端口（如 4096）可能被其他程序占用。随机端口由系统自动分配，几乎不会冲突。

### Q: Telegram 和飞书能同时运行吗？

**A**: 可以。两者使用不同的运行时、配置目录和网络协议。Telegram 启动脚本始终创建专用的 `opencode serve`；即使两个通道使用同一个项目目录，也不会复用同一个 serve 进程。

### Q: 多台电脑可以共用同一个 Telegram Bot Token 吗？

**A**: 可以，只要不同时使用。Telegram Bot 使用长轮询；同一 Token 同时运行多个实例会争抢 updates，并可能产生 `getUpdates` 冲突。Bot Token 可以跨机器复用，但切换前应先停止旧机器上的实例。

切换机器时，只需：
1. 确认旧机器的 Bot 已停止（或本身就没在运行）
2. 在新机器上运行 `opencode-telegram config`，填入同一个 Token 和 User ID
3. 运行启动脚本，Bot 即接管消息接收

### Q: 启动后出现 `409: Conflict: terminated by other getUpdates request` 怎么办？

**A**: 这表示同一个 Bot Token 正在被另一个长轮询实例使用。它不是 OpenCode 端口冲突、SQLite 问题，也不是 `opencode serve` 启动失败。

**脚本会自动处理**：启动脚本会检测本机是否已有 opencode-telegram 进程在运行，若有则自动停止旧实例后再启动新实例。如果自动清理失败，才会提示你手动处理。

如果自动清理后仍出现冲突，通常是另一台电脑、远程主机、daemon/service 或旧终端仍在使用同一个 Token。停止旧实例后再启动；如果找不到旧实例，去 @BotFather 撤销并重新生成 Bot Token，然后运行 `opencode-telegram config` 更新配置。

并行使用多台电脑时，建议每台电脑创建独立 Telegram Bot Token。

### Q: 一个从没在 OpenCode 打开过的新项目，怎么让它出现在 `/projects`？

**A**: 最稳妥的方法是先用该项目目录启动 Telegram 专用的 `opencode serve`，再在 Telegram 里切换项目。

方式一（推荐，使用启动脚本）：

```powershell
.\start-opencode-remote.ps1 -WorkingDir "D:\Code\YourNewProject"
```

方式二（手动）：

```powershell
cd D:\Code\YourNewProject
opencode serve --port 62489

# 新开一个终端
$env:OPENCODE_API_URL = "http://127.0.0.1:62489"
$env:NODE_USE_SYSTEM_CA = "1"
node "$env:APPDATA\npm\node_modules\@grinev\opencode-telegram-bot\dist\cli.js" start
```

然后在 Telegram 中执行：
1. `/projects`（刷新并选择新项目）
2. `/new`（创建新会话）或 `/sessions`（切换已有会话）

说明：`/projects` 列表来自 OpenCode API 项目列表与会话目录缓存合并结果。仅在文件系统里存在目录，不一定会立即出现在列表中；先以该目录启动一次 `serve` 最稳定。

### Q: 重启电脑后，之前的对话还在吗？

**A**: 在。对话历史持久化在磁盘（`~/.local/share/opencode/opencode.db`），不依赖 serve 进程。

## 多通道并行

本仓库设计支持多通道并行。Telegram 和飞书可以同时运行，互不干扰。详见 [OpenCode 总览文档](../README.md#通道对比)。

## 相关链接

- [opencode-telegram-bot 项目](https://github.com/grinev/opencode-telegram-bot)
- [Telegram Bot 调研报告](../../../docs/telegram-bot-research.md)
- [飞书通道可靠性记录](../../../docs/feishu-reliability.md)
- [环境配置指南](../docs/setup.md)
