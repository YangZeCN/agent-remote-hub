# OpenCode + 飞书通道

通过飞书（Feishu）远程操控 OpenCode AI 助手，实现手机端随时随地的代码协作。

## 架构原理

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

### 核心组件

- **opencode-lark**: 飞书消息桥接服务，监听飞书事件并转发给 OpenCode
- **opencode serve**: OpenCode 的 HTTP 服务端，提供 AI 对话能力
- **opencode TUI**: 本地终端界面，可与飞书共享同一会话上下文

### 会话持久化

- **对话历史**: 存储在 `~/.local/share/opencode/storage/`，独立于 serve 进程
- **飞书映射**: opencode-lark 的 `~/.config/opencode-lark/<hash>/data/sessions.db` 记录"飞书会话 ↔ OpenCode session"的对应关系（按项目 cwd 哈希隔离）
- **项目隔离**: session 按 serve 启动时的工作目录（cwd）隔离

## 快速开始

### 前置条件

- Node.js + npm
- Bun（opencode-lark 依赖）
- opencode（AI 引擎）
- opencode-lark（飞书桥接）
- 飞书应用凭证（App ID + App Secret）

### 新电脑环境配置（从零搭建）

以下按顺序执行，完成后即可运行 `.\start-opencode-remote.ps1`。

#### 1. 安装 Node.js

从 [Node.js 官网](https://nodejs.org/) 下载 LTS 版本安装（建议 >= 20）。安装后验证：

```powershell
node -v
npm -v
```

#### 2. 安装 Bun

Bun 是 opencode-lark 的运行环境。在 PowerShell 中执行：

```powershell
powershell -c "irm bun.sh/install.ps1 | iex"
```

安装后验证（默认装在 `~/.bun/bin`）：

```powershell
bun --version
```

> 如果 `bun` 命令找不到，把 `C:\Users\<你的用户名>\.bun\bin` 加到系统 PATH。

#### 3. 安装 opencode

```powershell
npm install -g opencode-ai
opencode --version
```

> 脚本实际调用的是 `opencode.exe`，路径为 `%APPDATA%\npm\node_modules\opencode-ai\bin\opencode.exe`。

#### 4. 安装 opencode-lark

```powershell
bun add -g opencode-lark
```

安装后验证：

```powershell
opencode-lark --version
```

> 实际二进制在 `~/.bun/bin/opencode-lark.exe`。

#### 5. 配置飞书应用凭证

opencode-lark 需要飞书应用的 App ID 和 App Secret 才能连接飞书。

**方式 A：QR 扫码（推荐，最简单）**

```powershell
opencode-lark run
```

首次运行会弹出二维码，用飞书扫码即可自动创建应用并完成配置。

**方式 B：手动配置**

1. 登录 [飞书开放平台](https://open.feishu.cn/)，创建一个企业自建应用
2. 在「凭证与基础信息」页面获取 **App ID** 和 **App Secret**
3. 在应用后台开启以下权限/能力：
   - 机器人能力
   - 事件订阅（WebSocket 模式）
   - 消息收发权限
4. 发布应用版本
5. 设置环境变量（或写入 opencode-lark 的配置文件）：

```powershell
$env:LARK_APP_ID = "你的 App ID"
$env:LARK_APP_SECRET = "你的 App Secret"
```

#### 6. 验证环境

```powershell
# 检查所有依赖
node -v
bun --version
opencode --version
opencode-lark --version
```

全部有输出后，就可以运行一键启动脚本了。

### 一键启动

```powershell
.\start-opencode-remote.ps1
```

脚本会自动：
1. 检测是否已有 `opencode serve` 在运行
2. 如果没有，启动一个新的 serve（随机端口）
3. 自动发现 serve 监听的端口
4. 如果端口 3001 已被占用，且占用进程是 `bun`/`opencode-lark`（旧桥接残留），自动停掉旧桥接
5. 启动 opencode-lark 并连接到该端口
6. 自动拉起绑定飞书 session 的 TUI 窗口
7. **保持运行**，脚本窗口会一直阻塞，直到你按 Ctrl+C 或 opencode-lark 退出
8. 退出时（Ctrl+C）自动清理**本脚本启动的** serve、opencode-lark（含其 `bun` 子进程）和 TUI；复用的已有 serve 不会动

> **退出行为说明**：
> - **按 Ctrl+C**：干净退出，停止本脚本启动的 serve + opencode-lark（连同持有端口 3001 的 `bun` 子进程一起杀掉）+ 关闭 TUI 窗口。
> - **直接点窗口 X 关闭**：PowerShell 的 finally 清理块可能不执行，opencode-lark 和 TUI 可能残留在后台。不过没关系——下次运行脚本时会自动检测并停掉端口 3001 上的旧桥接，所以脚本是幂等的、可以反复运行。

#### 指定项目目录

默认情况下，`opencode serve` 会继承运行脚本时 PowerShell 的当前目录（cwd）。由于 opencode 的 session 按 cwd 隔离，**在不同目录下运行脚本，对应的是不同项目的上下文**。

**具体例子：**

```powershell
# 场景 A：不加参数，继承当前目录
cd C:\Projects\MyApp
.\C:\Users\MrYang\Desktop\RemoteCopilot\start-opencode-remote.ps1
# → serve 的项目根是 C:\Projects\MyApp（继承当前目录）
# → 飞书消息会操作 MyApp 的代码

# 场景 B：加 -WorkingDir 参数，指定任意项目目录
#    无论当前在哪个目录，serve 都会使用你指定的路径
cd C:\Anywhere
.\C:\Users\MrYang\Desktop\RemoteCopilot\start-opencode-remote.ps1 -WorkingDir "C:\Projects\MyApp"
# → serve 的项目根是 C:\Projects\MyApp（你指定的路径）
# → 飞书消息会操作 MyApp 的代码
```

使用 `-WorkingDir` 参数可以显式指定 opencode serve 的工作目录：

```powershell
.\start-opencode-remote.ps1 -WorkingDir "C:\Projects\MyApp"
```

这样无论你在哪个目录运行脚本，serve 都会以你指定的目录作为项目根目录。

> 说明：传入 `-WorkingDir` 时，脚本会强制启动新的 serve（不会复用已有 serve），以确保 cwd 一定是你指定的目录。

### 手动启动

```powershell
# 1. 启动 serve（随机端口）
opencode serve

# 2. 查看 serve 监听的端口
Get-NetTCPConnection -State Listen | Where-Object { $_.OwningProcess -eq (Get-Process opencode).Id }

# 3. 设置环境变量并启动 opencode-lark
$env:OPENCODE_SERVER_URL = "http://127.0.0.1:<端口>"
opencode-lark
```

## TUI 与 Serve 绑定

默认情况下，本地 TUI 和飞书使用**不同的 session**，上下文不共享。要让它们共享对话历史，**TUI 必须用 `attach` 模式连接到 serve** 并指定同一个 session ID，而不是直接运行 `opencode`。

### 脚本已自动处理（推荐）

`start-opencode-remote.ps1` 会自动完成绑定，你**无需手动操作**：

1. 启动（或复用）`opencode serve`，拿到随机端口（传 `-WorkingDir` 时会强制新启）
2. 启动 `opencode-lark`，等它绑定/复用飞书 session
3. 通过 serve 的 REST API（`GET /session`）查找标题以 `Feishu chat` 开头、最近更新的 session
4. 自动执行 `opencode attach <url> --session <id>` 拉起一个绑定同一 session 的 TUI 窗口

也就是说，直接运行脚本，就会同时得到「飞书遥控」和「本地 TUI」，且两者共享上下文。

### session 是怎么被发现的？

opencode-lark 给自己的 session 起的标题固定是 `Feishu chat <chat_id>`。脚本用这个特征从 serve API 里过滤出来，因此**即使 opencode-lark 复用的是已存在的 session**（`is_bound: 1`，不会打印 `Observing session` 日志），也能可靠拿到 ID。

> 早期版本靠解析 opencode-lark 的 stdout 日志找 session，但复用会话时不会打印该日志，所以会失败。现在改用 API 查询，不再依赖日志或被 WAL 锁住的 `sessions.db`。

### 手动绑定（备用）

如果脚本未能自动拉起 TUI，可以手动连接：

```powershell
# 1. 查看 serve 端口
$port = (Get-NetTCPConnection -State Listen | Where-Object { $_.OwningProcess -eq (Get-Process opencode).Id }).LocalPort

# 2. 从 API 里找飞书 session ID
$sid = (Invoke-RestMethod "http://127.0.0.1:$port/session" -Headers @{Accept='application/json'} |
    Where-Object { $_.title -like 'Feishu chat*' } |
    Sort-Object { $_.time.updated } -Descending | Select-Object -First 1).id

# 3. 用 attach + session ID 启动 TUI
opencode attach "http://127.0.0.1:$port" --session $sid
```

### 验证绑定

启动后，在飞书发送消息，TUI 应该能看到相同的对话；在 TUI 输入，飞书也能看到。如果看不到，说明连接的不是同一个 session。

## 常见问题

### Q: 为什么用随机端口而不是固定端口？

**A**: 避免端口冲突。固定端口（如 4096）可能被其他程序占用（比如 Kilo Code 扩展），导致启动失败。随机端口由系统自动分配，几乎不会冲突。

### Q: 脚本启动后，serve 进程还在后台，正常吗？

**A**: 正常。脚本会记录自己启动的 serve 进程，在脚本退出时（包括 Ctrl+C）自动清理。如果你看到遗留的 serve，可能是：
- 旧版本脚本没有清理逻辑
- 手动启动的 serve（脚本不会动它）

手动清理（含 opencode-lark 及其 `bun` 子进程）：
```powershell
# 杀掉所有 opencode 相关进程（包括持有端口 3001 的 bun）
Get-Process opencode,opencode-lark,bun -ErrorAction SilentlyContinue | Stop-Process -Force
```

### Q: 飞书和 TUI 的上下文不共享？

**A**: 检查是否绑定了同一个 session：
1. 确认 TUI 用 `opencode attach` 启动，而不是直接 `opencode`
2. 确认连接的 URL 和端口与 opencode-lark 一致
3. 查看脚本输出中的 session ID（如 `ses_085118b57ffetRAlC0YfeycQNZ`），确保 TUI 也连接到该 session

### Q: 突然飞书和 TUI 分裂成两个 session、历史对不上了？

**A**: 通常是 **opencode-lark 的 data 目录中途变了**导致的。

**原因**：opencode-lark 用其工作目录下的 `data/sessions.db` 保存"飞书群聊 → opencode session"的映射。如果这个 data 目录发生变化（例如从旧的 `<项目>/data` 切换到了 `~/.config/opencode-lark/<hash>/data`，或换了 `-WorkingDir` / 从不同 cwd 启动导致哈希不同），opencode-lark 会读到一个**空的映射库**，找不到"接着用哪个 session"，于是**新建一个 session**。而 TUI 检测到的仍是旧 session，两边就分裂了。

**恢复（保留历史）**：把带历史的旧 `data` 覆盖到脚本当前正在用的目录即可。

1. 先停掉 opencode-lark（连 `bun` 子进程一起）释放数据库锁：
   ```powershell
   Get-Process opencode-lark,bun -ErrorAction SilentlyContinue | Stop-Process -Force
   ```
2. 算出当前 cwd 对应的 hash 目录（与脚本算法一致）：
   ```powershell
   $cwd = (Get-Location).Path
   $ms = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($cwd.ToLowerInvariant()))
   $hash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash.Substring(0,16); $ms.Dispose()
   $dst = "$env:USERPROFILE\.config\opencode-lark\$hash\data"
   ```
3. 用旧 data 覆盖 hash 目录（`sessions.db` 的 db/-wal/-shm 三个文件一起拷，保证一致）：
   ```powershell
   Copy-Item "$cwd\data\*" $dst -Force
   ```
4. 重跑脚本，opencode-lark 会读回原映射、复用老 session，TUI 也会检测到同一个，恢复同步。

**如何判断哪份是历史**：`sessions.db-wal` 文件更大、修改时间更早的那份是真历史；刚创建、很小的是空库。把大的那份覆盖到脚本当前使用的目录即可。

> **不想保留历史**：直接在飞书发条新消息让它在新 session 上重新开始，再重跑脚本让 TUI attach 到这个新 session 即可，老对话丢弃。

### Q: 重启电脑后，之前的对话还在吗？

**A**: 在。对话历史持久化在磁盘（`~/.local/share/opencode/storage/`），不依赖 serve 进程。只要从同一个目录启动 serve，session 作用域就一致，上下文能续上。

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

## 文件说明

- `start-opencode-remote.ps1` - 一键启动脚本
- `~/.config/opencode-lark/<hash>/data/` - opencode-lark 数据目录（sessions.db, memory.db），按项目 cwd 哈希隔离
- `~/.local/share/opencode/` - OpenCode 全局存储（session 历史）

> **数据目录说明**：脚本会根据当前工作目录（或 `-WorkingDir` 指定的目录）的 SHA256 哈希，在 `~/.config/opencode-lark/` 下创建对应的子目录。同一项目目录始终复用同一份数据，不同项目目录互不干扰。

## 相关链接

- [OpenCode 官方文档](https://github.com/opencode-ai/opencode)
- [opencode-lark 项目](https://github.com/guazi04/opencode-lark)
- [飞书开放平台](https://open.feishu.cn/)
