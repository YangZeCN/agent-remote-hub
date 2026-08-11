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

> **重要：`-WorkingDir` 不会自动切换 Telegram 里的当前项目。** 它只设置本脚本启动的 `opencode serve` 的工作目录，使该目录作为一个项目出现在 `/projects` 列表中。Telegram bot 的“当前项目/会话”保存在 `%APPDATA%\opencode-telegram-bot\settings.json`，与 serve 的 cwd 相互独立。启动时 bot 会**恢复上一次的会话**（可能是旧目录），本地 TUI 也会 attach 到那个已存在的会话，因此会显示旧目录而不是 `-WorkingDir` 指定的目录。
>
> 要真正切换到该目录，必须在 Telegram 里手动操作：
> 1. `/projects` → 选择目标项目（这一步才会写入并持久化“当前项目”）
> 2. `/new` 新建会话（会话目录 = 所选项目的 worktree）
>
> 完成后本地 TUI 会自动重启并 attach 到新会话，显示正确的目录。

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

## 网络配置

Bot 需要访问 `api.telegram.org`。在国内网络环境下，必须配置代理或专线，否则 Bot 会卡在 `Waiting for Telegram bot session...`，日志中显示 `Network request for 'setMyCommands' failed!`。

### 方式一：本地代理（推荐）

适用于本机运行了 v2rayN、Clash、SSR 等代理软件的情况。编辑 `%APPDATA%\opencode-telegram-bot\.env`，取消注释并填写代理地址：

```env
# HTTP/HTTPS 代理（Clash 默认端口 7890，v2rayN 默认端口 10808）
TELEGRAM_PROXY_URL=http://127.0.0.1:10808

# SOCKS5 代理（如 v2rayN 的 SOCKS 端口）
# TELEGRAM_PROXY_URL=socks5://127.0.0.1:1080
```

> **提示**：不确定代理端口？运行以下命令扫描常见端口：
> ```powershell
> @(7890,7891,1080,10808,10809,20170,20171,10801,10802) | ForEach-Object {
>     if ((Test-NetConnection 127.0.0.1 -Port $_ -WarningAction SilentlyContinue).TcpTestSucceeded) {
>         Write-Host "Port $_ : OPEN"
>     }
> }
> ```

### 方式二：Windows 双网卡分流

适用于无线网卡连接国内网络、有线网卡连接海外专线的 Windows 主机。配置只修改运行 Bot 的本机路由表，不需要修改交换机。目标是让系统默认流量继续走无线网络，仅将 Telegram Bot API 流量送往有线专线。

> 以下命令需要在管理员 PowerShell 中执行。先使用临时路由验证，确认 Bot 能正常收发消息后再写入永久路由。

适用于无线网卡连接国内网络、有线网卡连接海外专线的 Windows 主机。配置只修改运行 Bot 的本机路由表，不需要修改交换机。目标是让系统默认流量继续走无线网络，仅将 Telegram Bot API 流量送往有线专线。

> 以下命令需要在管理员 PowerShell 中执行。先使用临时路由验证，确认 Bot 能正常收发消息后再写入永久路由。

### 1. 确认接口、网关和默认出口

```powershell
Get-NetIPConfiguration |
       Select-Object InterfaceAlias,InterfaceIndex,
              @{N='IPv4';E={$_.IPv4Address.IPAddress -join ','}},
              @{N='Gateway';E={$_.IPv4DefaultGateway.NextHop -join ','}}

Get-NetRoute -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 |
       Sort-Object RouteMetric
```

无线网卡的默认路由 Metric 应小于有线网卡。Metric 越小，默认路由优先级越高。仅在当前优先级不正确时才调整，例如：

```powershell
Set-NetIPInterface -InterfaceAlias 'Wi-Fi 2' -AddressFamily IPv4 `
       -AutomaticMetric Disabled -InterfaceMetric 10
Set-NetIPInterface -InterfaceAlias 'Ethernet' -AddressFamily IPv4 `
       -AutomaticMetric Disabled -InterfaceMetric 20
```

### 2. 添加临时 Telegram 路由

将变量替换为本机实际的有线接口索引和网关。`ActiveStore` 路由会在重启后消失：

```powershell
$interfaceIndex = 19
$gateway = '10.144.130.1'
$telegramPrefix = '149.154.160.0/20'

New-NetRoute -DestinationPrefix $telegramPrefix `
       -InterfaceIndex $interfaceIndex `
       -NextHop $gateway `
       -RouteMetric 5 `
       -PolicyStore ActiveStore
```

验证目标地址确实通过有线网卡，并测试 TCP 443：

```powershell
Find-NetRoute -RemoteIPAddress 149.154.167.220 |
       Format-List InterfaceAlias,InterfaceIndex,NextHop,RouteMetric

Test-NetConnection 149.154.167.220 -Port 443 |
       Format-List RemoteAddress,InterfaceAlias,SourceAddress,TcpTestSucceeded
```

### 3. 绕过受污染的 DNS

如果 `Resolve-DnsName api.telegram.org` 返回的不是 Telegram 地址，可在 `%WINDIR%\System32\drivers\etc\hosts` 中固定一个已经通过 HTTPS 验证的 Bot API 地址：

```text
149.154.167.220 api.telegram.org
```

修改前必须备份 Hosts，修改后执行：

```powershell
Clear-DnsClientCache
Resolve-DnsName api.telegram.org -Type A
Test-NetConnection api.telegram.org -Port 443
```

Hosts 中写入多个同名地址不等于健康检查或自动故障切换。该地址失效时需要重新验证并更新；若需要自动容错，优先使用 `TELEGRAM_PROXY_URL` 或自建 `TELEGRAM_API_ROOT`。

### 4. 固化与回滚

Bot 实际收发消息和文件验证通过后，删除临时路由并写入永久路由：

```powershell
Remove-NetRoute -DestinationPrefix $telegramPrefix `
       -InterfaceIndex $interfaceIndex -PolicyStore ActiveStore -Confirm:$false

New-NetRoute -DestinationPrefix $telegramPrefix `
       -InterfaceIndex $interfaceIndex `
       -NextHop $gateway `
       -RouteMetric 5 `
       -PolicyStore PersistentStore
```

专线故障、网关变化或需要恢复默认选路时，删除 Telegram 路由，并恢复修改前备份的 Hosts：

```powershell
Get-NetRoute -DestinationPrefix $telegramPrefix -ErrorAction SilentlyContinue |
       Remove-NetRoute -Confirm:$false
Clear-DnsClientCache
```

静态路由本身不会检测专线健康状态。如果有线链路仍处于连接状态但专线上游不可达，Windows 不一定自动回退到无线网络，因此生产部署仍需监控 TCP 443 和 Bot 日志。

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

**A**: `/projects` 只列出 OpenCode 已知的项目（API 项目列表 + 会话目录缓存）。一个从没建过会话的全新目录，仅靠 `-WorkingDir` 启动 serve **不一定**会出现在里面。最可靠的做法是用 `/open` 浏览目录并选中它——选中后 bot 会把该目录注册为项目、切换为当前项目，之后它就会出现在 `/projects`。

> **D 盘（或主目录以外）无法浏览？** `/open` 的可浏览范围由环境变量 `OPEN_BROWSER_ROOTS` 决定，**默认只有用户主目录（C 盘 `C:\Users\<你>`）**。要浏览 D 盘，需在 `%APPDATA%\opencode-telegram-bot\.env` 里配置（逗号分隔多个根）：
>
> ```env
> OPEN_BROWSER_ROOTS=C:\Users\<你>,D:\Code
> ```
>
> 保存后重启 bot（重跑启动脚本）。配置多个根时，`/open` 会先让你选择根目录，再逐级进入，选中目标文件夹即可。

如果目录已经建过会话（在 `/projects` 里能看到），直接 `/projects` 选择即可，无需 `/open`。

以下两种方式适用于该目录**已经有历史会话**、只是想用指定目录启动专用 serve 的情况：

方式一（使用启动脚本）：

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

**接着这一步不能省略**，必须在 Telegram 中手动切换项目：
1. `/projects`（刷新并选择新项目）— 只有这一步会把该目录写入 bot 的“当前项目”并持久化到 `settings.json`
2. `/new`（在该项目下创建新会话）或 `/sessions`（切换已有会话）

> **为什么只加 `-WorkingDir` 不够？** bot 的会话目录来自它自己持久化的“当前项目”，而不是 `opencode serve` 的 cwd。`-WorkingDir` 只设置 serve 的 cwd，不会自动切换 bot 的当前项目，也不保证全新目录立即出现在 `/projects`；bot 启动时仍会恢复上一次的会话（可能是旧目录），本地 TUI 也会 attach 到那个旧会话。全新目录请优先用上面的 `/open` 浏览方式添加。

### Q: 重启电脑后，之前的对话还在吗？

**A**: 在。对话历史持久化在磁盘（`~/.local/share/opencode/opencode.db`），不依赖 serve 进程。

## 多通道并行

本仓库设计支持多通道并行。Telegram 和飞书可以同时运行，互不干扰。详见 [OpenCode 总览文档](../README.md#通道对比)。

## 相关链接

- [opencode-telegram-bot 项目](https://github.com/grinev/opencode-telegram-bot)
- [Telegram Bot 调研报告](../../../docs/telegram-bot-research.md)
- [飞书通道可靠性记录](../../../docs/feishu-reliability.md)
- [环境配置指南](../docs/setup.md)
