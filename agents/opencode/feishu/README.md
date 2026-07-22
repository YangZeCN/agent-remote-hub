# OpenCode + 飞书通道

通过飞书（Feishu）远程操控 OpenCode AI 助手，实现手机端随时随地的代码协作。

> **可靠性提示**：当前 `opencode-lark` 存在已确认的延迟 ACK 与去重窗口问题，同一条飞书消息可能在数小时后被重新提交给 OpenCode。执行发布、推送、删除等不可逆操作前请保留人工确认。根因、临时处置和上游修复建议见 [飞书通道可靠性记录](../../../docs/feishu-reliability.md)。

## 架构原理

```
┌─────────────┐
│  飞书客户端  │  ← 手机/电脑
└──────┬──────┘
   │ 飞书消息协议
       ▼
┌─────────────────────┐
│  飞书开放平台        │  ← 消息路由
└──────┬──────────────┘
       │ WebSocket
       ▼
┌─────────────────────┐
│  opencode-lark      │  ← 飞书 ↔ OpenCode 桥接
│  (本地监听 3001)    │
└──────┬──────────────┘
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

- **opencode-lark**: 飞书消息桥接服务，监听飞书事件并转发给 OpenCode
- **opencode serve**: OpenCode 的 HTTP 服务端，提供 AI 对话能力
- **opencode TUI**: 本地终端界面，可与飞书共享同一会话上下文

### 会话持久化

- **对话历史**: 当前 OpenCode 将数据存储在 `~/.local/share/opencode/opencode.db`（以及 SQLite WAL 文件），独立于 serve 进程
- **飞书映射**: opencode-lark 的 `~/.config/opencode-lark/<hash>/data/sessions.db` 记录"飞书会话 ↔ OpenCode session"的对应关系（按项目 cwd 哈希隔离）
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

## 快速开始

### 前置条件

- Node.js 20 或更高版本。
- Bun、OpenCode 和 `opencode-lark`。
- 已发布并完成权限配置的飞书应用。

首次安装参考 [环境配置指南](../docs/setup.md) 和 [飞书应用创建指南](../../../docs/feishu-setup.md)。本页不重复维护安装步骤。

启动前可快速验证：

```powershell
node -v
bun --version
opencode --version
Get-Item "$env:USERPROFILE\.bun\bin\opencode-lark.exe"
```

> 当前 `opencode-lark` 没有独立的 `--version` 行为；执行 `opencode-lark --version` 会直接启动 bridge，不要用它检查版本。

### 一键启动

```powershell
.\start-opencode-remote.ps1
```

脚本会自动：
1. 检测是否已有工作目录与目标项目一致的 `opencode serve` 在运行
2. 如果没有匹配项，启动一个新的 serve（随机端口）
3. 自动发现 serve 监听的端口
4. 如果端口 3001 已被占用，且占用进程是 `bun`/`opencode-lark`（旧桥接残留），自动停掉旧桥接
5. 启动 opencode-lark 并连接到该端口
6. 收到第一条飞书消息、创建/绑定 session 后，自动拉起对应的 TUI 窗口
7. **保持运行**，脚本窗口会一直阻塞，直到你按 Ctrl+C 或 opencode-lark 退出
8. 退出时（Ctrl+C）自动清理**本脚本启动的** serve、opencode-lark（含其 `bun` 子进程）和 TUI；复用的已有 serve 不会动

> **退出行为说明**：
> - **按 Ctrl+C**：干净退出，停止本脚本启动的 serve + opencode-lark（连同持有端口 3001 的 `bun` 子进程一起杀掉）+ 关闭 TUI 窗口。
> - **直接点窗口 X 关闭**：PowerShell 的 finally 清理块可能不执行，opencode-lark 和 TUI 可能残留在后台。不过没关系——下次运行脚本时会自动检测并停掉端口 3001 上的旧桥接，所以脚本是幂等的、可以反复运行。

#### 指定项目目录

默认情况下，`opencode serve` 使用当前 PowerShell 目录。由于 OpenCode session 按工作目录隔离，建议显式传入项目路径：

```powershell
.\start-opencode-remote.ps1 -WorkingDir "C:\Projects\MyApp"
```

脚本只复用 API 返回目录与目标目录完全一致的 serve；没有匹配项时才启动新实例。

> **不要让正在运行的 OpenCode/飞书会话执行本脚本来切换项目。** 该任务是旧 serve 的子进程；切换 bridge 后，旧管理脚本会清理整个 serve 进程树，导致切换任务被中途终止。脚本会检测这种调用并安全退出。请在独立 PowerShell 窗口中执行切换命令。

### 手动启动

不建议手动拼接启动命令。除了 `OPENCODE_SERVER_URL`，脚本还负责设置 `OPENCODE_CWD`、按项目创建 bridge 数据目录、校验复用的 serve、处理端口 3001 冲突和清理进程。遗漏其中任一步都可能导致项目串线或 session 映射分裂。

如需调试，请先运行一键脚本，再根据输出中的 Server URL、数据目录和日志路径检查对应进程。

## TUI 与 Serve 绑定

默认情况下，本地 TUI 和飞书使用**不同的 session**，上下文不共享。要让它们共享对话历史，**TUI 必须用 `attach` 模式连接到 serve** 并指定同一个 session ID，而不是直接运行 `opencode`。

### 脚本已自动处理（推荐）

`start-opencode-remote.ps1` 会自动完成绑定，你**无需手动操作**：

1. 启动（或复用工作目录一致的）`opencode serve`，拿到监听端口
2. 启动 `opencode-lark`，等它绑定/复用飞书 session
3. 从 opencode-lark 的 `Observing session <id> for chat <id>` 日志取得精确 session ID，并通过 serve API 校验其项目目录
4. 自动执行 `opencode attach <url> --session <id>` 拉起一个绑定同一 session 的 TUI 窗口

也就是说，直接运行脚本，就会同时得到「飞书遥控」和「本地 TUI」，且两者共享上下文。

### session 是怎么被发现的？

opencode-lark 在收到飞书消息并开始观察对应 session 时，会固定输出 `Observing session <id> for chat <id>`。脚本从本次启动的独立日志中读取该 ID，再调用 `GET /session/<id>` 校验 session 的 `directory` 与目标项目一致。这样不会靠标题和更新时间猜测，也不会直接读取或修改 WAL 模式下的 `sessions.db`。

### 手动绑定（备用）

如果脚本没有自动拉起 TUI，从脚本输出或 `%TEMP%\opencode-lark-stdout.log` 中取得 `Observing session <id> for chat <id>` 对应的 session ID，再连接脚本输出的 Server URL：

```powershell
opencode attach "http://127.0.0.1:<脚本输出的端口>" --session <日志中的-session-id>
```

不要按 session 标题或“最近更新时间”猜测；不同项目或其他客户端可能产生相似标题。

### 验证绑定

启动后，在飞书发送消息，TUI 应该能看到相同的对话；在 TUI 输入，飞书也能看到。如果看不到，说明连接的不是同一个 session。

## 常见问题

### Q: 为什么用随机端口而不是固定端口？

**A**: 避免端口冲突。固定端口（如 4096）可能被其他程序占用（比如 Kilo Code 扩展），导致启动失败。随机端口由系统自动分配，几乎不会冲突。

### Q: 脚本启动后，serve 进程还在后台，正常吗？

**A**: 正常。脚本会记录自己启动的 serve 进程，在脚本退出时（包括 Ctrl+C）自动清理。如果你看到遗留的 serve，可能是：
- 旧版本脚本没有清理逻辑
- 手动启动的 serve（脚本不会动它）

不要批量停止所有 `opencode` 或 `bun` 进程，这可能误伤其他项目和工具。优先关闭原启动窗口；旧 bridge 占用 3001 时，重新运行脚本会先校验进程身份，再只清理对应的 bridge 进程树。

### Q: 飞书和 TUI 的上下文不共享？

**A**: 检查是否绑定了同一个 session：
1. 确认 TUI 用 `opencode attach` 启动，而不是直接 `opencode`
2. 确认连接的 URL 和端口与 opencode-lark 一致
3. 查看脚本输出中的 session ID（如 `ses_085118b57ffetRAlC0YfeycQNZ`），确保 TUI 也连接到该 session

### Q: 突然飞书和 TUI 分裂成两个 session、历史对不上了？

**A**: 通常是 **opencode-lark 的 data 目录中途变了**导致的。

**原因**：opencode-lark 用其工作目录下的 `data/sessions.db` 保存"飞书群聊 → opencode session"的映射。如果这个 data 目录发生变化（例如从旧的 `<项目>/data` 切换到了 `~/.config/opencode-lark/<hash>/data`，或换了 `-WorkingDir` / 从不同 cwd 启动导致哈希不同），opencode-lark 会读到一个**空的映射库**，找不到"接着用哪个 session"，于是**新建一个 session**。而 TUI 检测到的仍是旧 session，两边就分裂了。

**恢复（保留历史）**：不要直接覆盖数据库。先停止 bridge，并备份所有候选数据目录：

1. 先停掉 opencode-lark（连 `bun` 子进程一起）释放数据库锁：
   ```powershell
   Get-Process opencode-lark,bun -ErrorAction SilentlyContinue | Stop-Process -Force
   ```
2. 算出当前项目对应的数据目录（与脚本算法一致）：
   ```powershell
   $cwd = (Get-Location).Path
   $ms = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($cwd.ToLowerInvariant()))
   $hash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash.Substring(0,16); $ms.Dispose()
   $dst = "$env:USERPROFILE\.config\opencode-lark\$hash\data"
   ```
3. 备份当前目标目录：
   ```powershell
   Copy-Item $dst "$dst.backup" -Recurse
   ```
4. 对其他疑似旧目录也分别做完整备份。不要只凭文件大小或修改时间判断哪份数据正确，也不要单独复制 `sessions.db-wal` 或 `sessions.db-shm`。
5. 使用 SQLite 工具核对实际 chat/session 映射。确认来源后，再在 bridge 已停止的情况下迁移完整 `data` 目录。
6. 重跑脚本，在飞书发送测试消息，并确认日志中的 session ID 与预期一致。

如果无法确认数据库内容，保留备份并新建 session 比猜测后覆盖更安全。

> **不想保留历史**：直接在飞书发条新消息让它在新 session 上重新开始，再重跑脚本让 TUI attach 到这个新 session 即可，老对话丢弃。

### Q: 重启电脑后，之前的对话还在吗？

**A**: 在。对话历史持久化在磁盘（当前为 `~/.local/share/opencode/opencode.db`），不依赖 serve 进程。只要从同一个目录启动 serve，session 作用域就一致，上下文能续上。

### Q: 多个飞书群聊，上下文会混吗？

**A**: 不会。opencode-lark 为每个飞书群聊维护独立的 session 映射（存在 `data/sessions.db`），互不干扰。

### Q: 脚本启动失败，提示 "opencode-lark not found"？

**A**: 安装 opencode-lark：
```powershell
bun add -g opencode-lark
```

### Q: 如何查看 opencode-lark 的日志？

**A**: 脚本把 opencode-lark 的 stdout/stderr 重定向到了临时文件：
- stdout: `%TEMP%\opencode-lark-stdout.log`
- stderr: `%TEMP%\opencode-lark-stderr.log`

实时查看：
```powershell
Get-Content "$env:TEMP\opencode-lark-stdout.log" -Tail 20 -Wait
```

### Q: 能否同时运行多个 opencode-lark 实例？

**A**: 不能。opencode-lark 独占端口 3001，同一时刻只能有一个实例。脚本会自动检测并停掉端口 3001 上的旧桥接再启动新的，所以反复运行脚本是安全的（幂等）。一个 opencode-lark 可以同时服务多个飞书群聊。

### Q: 如何更新 opencode-lark？

**A**: 
```powershell
bun update -g opencode-lark
```

## 已知限制：斜杠命令交互

### 问题描述

OpenCode 支持一些斜杠命令（如 `/new`、`/models` 等），在 OpenCode 客户端（TUI/Web）中输入 `/` 时会自动弹出命令提示。但在飞书中：

- ❌ 输入 `/` 时**不会弹出命令菜单**
- ❌ 没有自动补全提示
- ✅ 手动输入完整命令（如 `/new`）后**功能正常**

### 原因分析

这是**飞书平台本身的限制**，不是 opencode-lark 的配置问题。

| 特性 | 飞书 | Telegram |
|------|------|----------|
| 输入 `/` 时弹出命令菜单 | ❌ 不支持 | ✅ 原生支持 |
| 命令自动补全提示 | ❌ 无 | ✅ 有，显示命令描述 |
| 命令注册机制 | 需要开发"机器人菜单"按钮 | BotFather 注册命令列表即可 |
| 手动输入命令发送 | ✅ 可以正常工作 | ✅ 可以正常工作 |

### 改进方向

| 方案 | 难度 | 效果 |
|------|------|------|
| **飞书消息卡片按钮** | 中等 | 在回复中嵌入按钮（如"新会话"、"切换模型"），用户点击即可，不需要手动输入命令 |
| **飞书机器人菜单** | 中等 | 在飞书聊天窗口顶部添加机器人菜单按钮，点击触发命令 |
| **切换到 Telegram** | 低 | 直接用 Telegram 的斜杠命令系统，但需要搭建 Telegram Bot |
| **动态 /help 命令** | 低 | 实现 `/help` 命令，查询 OpenCode 当前可用的 Skills 并返回命令列表 |
| **保持现状** | 无 | 手动输入命令，功能完全正常，只是没有提示 |

### 当前建议

- **功能不受影响**：手动输入 `/new`、`/models` 等命令在飞书中完全可用
- **手机端使用**：如果主要在手机上操作，建议记住常用命令，或考虑切换到 Telegram
- **后续优化**：可以通过消息卡片按钮或机器人菜单来改善飞书的交互体验
- Telegram 的完整交互和网络评估见 [OpenCode Telegram Bot 调研](../../../docs/telegram-bot-research.md)

## 已知限制：消息重放

飞书平台可能在 WebSocket ACK 不及时后重新投递旧事件。当前 bridge 会等待较长的 OpenCode 业务处理，而且持久化去重窗口只有 60 秒，因此数小时后的重放可能再次触发相同 Prompt。

这不是启动脚本能够完整修复的问题。当前建议：

- 不让无人值守任务直接执行部署、推送或删除等不可逆操作。
- 尽量让自动化命令具备幂等性。
- 发现旧命令再次执行时先中止 Agent，并从日志核对相同的 `message_id`。
- 跟踪上游问题 [guazi04/opencode-lark#12](https://github.com/guazi04/opencode-lark/issues/12)。

完整分析和验收条件见 [飞书通道可靠性记录](../../../docs/feishu-reliability.md)。

## 文件说明

- `start-opencode-remote.ps1` - 一键启动脚本
- `~/.config/opencode-lark/<hash>/data/` - opencode-lark 数据目录（sessions.db, memory.db），按项目 cwd 哈希隔离
- `~/.local/share/opencode/opencode.db` - OpenCode 全局数据库（包含 session 历史）

> **数据目录说明**：脚本会根据当前工作目录（或 `-WorkingDir` 指定的目录）的 SHA256 哈希，在 `~/.config/opencode-lark/` 下创建对应的子目录。同一项目目录始终复用同一份数据，不同项目目录互不干扰。

## 相关链接

- [OpenCode 官方文档](https://github.com/opencode-ai/opencode)
- [opencode-lark 项目](https://github.com/guazi04/opencode-lark)
- [飞书开放平台](https://open.feishu.cn/)
- [飞书通道可靠性记录](../../../docs/feishu-reliability.md)
- [OpenCode Telegram Bot 调研](../../../docs/telegram-bot-research.md)
