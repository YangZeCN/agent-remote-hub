# 远程 AI 编程助手方案调研

> 文档说明：本文件是调研记录，包含阶段性结论。文中 Star 数、安装量、功能描述会随时间变化，请以项目仓库和官方文档为准。

## 一、需求描述

在电脑前用 VSCode + GitHub Copilot 写 Prompt 做开发，临时离开时，能通过手机端：
1. 看到 AI 的运行情况和结果
2. 根据结果提出新的 Prompt 指令
3. 继续控制 AI 完成后续任务

### 约束条件

- 电脑是 Windows，在公司网络（出站 SSH/HTTPS 允许，入站受限）
- 有自己的阿里云 ECS（国内）和域名
- ECS 不能访问海外（排除 Telegram）
- 有自己的模型，不想被工具绑定
- 不绑定 VSCode / Copilot，可以接受 OpenCode 等替代方案
- 手机不一定连 WiFi，人可能在公司也可能在外面
- 第一目标自用，后续可能分享

## 二、方案演进过程

### 方案 A：寄生在 Copilot Chat 上（❌ 放弃）

```
思路：写一个 VSCode 扩展，监听 Copilot Chat 的对话，转发到手机
```

**问题：**
- VSCode 扩展无法读取 Copilot Chat 面板的内容（那是另一个扩展的 webview）
- 无法直接向 Copilot Chat 注入消息
- 无法复用 Copilot 的 Agent 工具链（读文件、写文件、跑命令）
- 等于要自己重新造一个 Copilot，且和真正的 Copilot 是割裂的

### 方案 B：自建 Agent + Workspace 感知（❌ 放弃）

```
思路：不依赖 Copilot，自己调 LLM API + 注册工具，做一个能力等价的 Agent
```

**问题：**
- 用户对"做一个等价 Agent"没有信心
- 需要自己实现工具链（读文件、写文件、搜索、跑命令...）
- 上下文管理复杂
- 维护成本高

### 方案 C：远程控制 OpenCode（✅ 最终方案）

```
思路：用 OpenCode 作为 Agent 引擎，通过飞书远程操控
```

**优势：**
- OpenCode 是成熟的开源 Agent，工具链完整
- 支持自带模型，不绑定供应商
- 已有现成的飞书桥接方案，零代码搭建
- 全程国内，不需要翻墙，公司网络友好

## 三、技术调研：OpenCode 已有能力

调研发现 OpenCode 本身已经提供了完整的远程控制基础设施：

### opencode serve
- 启动无头 HTTP 服务器，暴露完整 OpenAPI 接口
- 支持认证（`OPENCODE_SERVER_PASSWORD`）
- 支持 CORS、mDNS

### opencode web
- 启动 Web 界面，浏览器直接使用
- 支持 `--hostname 0.0.0.0` 让外部访问

### opencode run
- 非交互模式，直接执行 prompt
- 可以 attach 到已运行的 serve 实例

### 完整 HTTP API
- Session 管理（创建/删除/fork）
- 消息收发（同步/异步）
- SSE 实时事件流
- 文件操作、搜索
- 工具调用（bash、file、grep...）

## 四、网络方案分析

### 方案对比

| 方案 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| cloudflared tunnel | 电脑主动连 Cloudflare，生成公网 URL | 免费、简单 | 中国无节点，延迟高，域名可能被墙 |
| SSH 反向隧道 | 电脑主动 SSH 到 ECS，映射端口 | 不需要公网 IP | 断线需重连，不稳定 |
| 阿里云 ECS 反代 | ECS 做 nginx 反代 + HTTPS | 速度可控，公司友好 | 需要配置 |
| 飞书/钉钉 Bot | Bot 主动连飞书服务器（出站） | 不需要隧道/反代 | 需要飞书应用配置 |

### 最终选择：飞书 Bot

```
原因：
- 不需要隧道，不需要开放端口
- Bot 程序主动连飞书（出站连接），公司防火墙不阻拦
- 飞书国内直连，速度快
- 公司网络通常允许飞书
- 有现成方案，配置简单
```

### 流量路径

```
┌──────────┐         ┌──────────────┐         ┌──────────┐
│  手机     │         │  飞书服务器   │         │  电脑     │
│  飞书App │◀───────▶│  (国内)      │◀────────│  bridge  │
│          │         │              │  出站WS │  程序    │
└──────────┘         └──────────────┘         └────┬─────┘
                                                   │
                                              ┌────▼─────┐
                                              │ opencode │
                                              │ serve    │
                                              │ localhost│
                                              └──────────┘

全程本地/国内，不需要阿里云，不需要隧道
```

## 五、现成方案调研

### 飞书方案

> 备注：下表中的 Star 数是调研时快照，只用于相对参考。

| 项目 | Stars | 特点 | 推荐度 |
|------|-------|------|--------|
| **lark-opencode-bridge** | 16 | 专注 OpenCode+飞书，QR 扫码配置，流式卡片，/spawn 工作群，文档评论集成，后台守护 | ★★★★★ |
| golembot | 310 | 多 Agent 通用（Cursor/Claude Code/OpenCode/Codex），支持 7 个平台 | ★★★★☆ |
| deepcoldy/botmux | 696 | 多 CLI 桥接，每个 DM 自动开 session，社区最活跃 | ★★★★☆ |

> **注意**：本仓库实际使用的是 [opencode-lark](https://github.com/guazi04/opencode-lark)（`guazi04/opencode-lark`），而非调研时推荐的 `lark-opencode-bridge`。两者功能类似但项目不同，`opencode-lark` 通过 npm 安装（`bun add -g opencode-lark`），配置方式也略有差异。

### 其他平台方案（参考）

| 项目 | 平台 | 说明 |
|------|------|------|
| opencode-remote-android | 专用 App | Android APK，直接调 OpenCode HTTP API |
| grinev/opencode-telegram-bot | Telegram | 949★（2026-07 快照），功能最完整，已在本仓库落地 |

## 六、推荐方案：opencode-lark（实际采用）

> 调研时推荐的是 `lark-opencode-bridge`，但本仓库最终采用的是 [opencode-lark](https://github.com/guazi04/opencode-lark)（`guazi04/opencode-lark`）。两者功能类似，但 `opencode-lark` 通过 npm/bun 安装，更轻量。

### 为什么选它

- 专门为 OpenCode + 飞书设计
- 通过 npm/bun 安装，配置简单
- 流式卡片：思考/工具调用/文本实时刷新
- 附件支持：发截图/文件给 AI 分析
- 支持 Windows
- 代码 100% 本地，不上传

### 工作原理

```
1. start-opencode-remote.ps1 启动 opencode serve（随机端口）
2. 启动 opencode-lark，建立飞书 WebSocket 长连接（出站，不需要开放端口）
3. 收到飞书消息 → 创建/复用 opencode session
4. 调用 opencode HTTP API 发送 prompt
5. 订阅 SSE 事件流，实时渲染到飞书卡片
6. 结果以流式卡片形式返回飞书
```

### 搭建步骤

详见 [环境配置指南](../agents/opencode/docs/setup.md) 和 [飞书通道文档](../agents/opencode/feishu/README.md)。

### 常用命令

| 飞书命令 | 说明 |
|----------|------|
| `/help` | 显示帮助 |
| `/new` | 重置当前 session |
| `/models` | 列出可用模型 |
| `/models provider/model` | 切换模型 |
| `/agents` | 列出可用 Agent |
| `/spawn <topic>` | 创建项目工作群 |
| `/cd <path>` | 切换工作目录 |
| `/stop` | 中止当前任务 |
| `/status` | 显示当前状态 |
| `/workspaces save/use` | 管理命名工作区 |

## 七、使用场景

### 场景 1：离开电脑，手机继续

```
1. 电脑前：正常用 VSCode + Copilot 开发
2. 要离开时：lark-opencode-bridge start（后台运行）
3. 在外面：打开飞书 App → 给机器人发 prompt
4. 看到流式卡片实时更新结果
5. 继续发新 prompt，迭代开发
```

### 场景 2：回到电脑前

```
1. 看飞书知道远程做了什么
2. 在 VSCode 里看到文件已经是最新的
3. 继续本地开发
```

### 场景 3：/spawn 工作群

```
1. 飞书里发 /spawn 重构登录模块
2. 自动创建一个群，绑定一个 session
3. 群里直接说话，不需要 @机器人
4. 随时回来继续，上下文还在
```

## 八、备选方案

### 如果以后想换

| 方案 | 适用场景 |
|------|----------|
| golembot | 想同时支持飞书+钉钉+企微+Telegram，或想切换 Agent（Cursor/Claude Code/Codex） |
| botmux | 想要更活跃的社区，或需要多 CLI 桥接 |
| opencode-remote-android + 阿里云 | 想要原生 App 体验，不依赖飞书 |

### 如果飞书方案不够用

- OpenCode 的 HTTP API 是开放的，可以自己写客户端
- 可以用 opencode-remote-android 作为补充（App 直连 OpenCode API）
- 可以升级到 golembot（更通用，支持更多平台和 Agent）

## 九、关键决策记录

| 决策点 | 选择 | 理由 |
|--------|------|------|
| Agent 引擎 | OpenCode | 开源、成熟、支持自带模型、有完整 HTTP API |
| 通信平台 | 飞书 | 国内直连、公司友好、有现成方案 |
| 桥接工具 | lark-opencode-bridge | 专注 OpenCode+飞书、配置简单、功能完整 |
| 网络方案 | 不需要（飞书 Bot 出站连接） | 不需要隧道/反代/阿里云中转 |
| 阿里云 ECS | 暂不需要 | 飞书 Bot 方案不需要中转服务器 |

## 十、VSCode + GitHub Copilot 原生远程控制方案

既然 VSCode + Copilot 是主力，必须评估 GitHub 官方的方案。

### 10.1 Copilot CLI + Remote Control（官方原生，⭐ 推荐）

**这是 GitHub 官方提供的原生远程控制功能，2026 年 7 月文档显示已可用。**

#### 是什么

Copilot CLI 是 VSCode 内置的后台 Agent 运行模式：
- Agent 在后台独立运行，不依赖 VSCode 窗口（关闭窗口也继续跑）
- 支持 Worktree 隔离（Git worktree，不干扰你的主工作区）
- 支持 Folder 模式（直接修改当前工作区）
- 可以并行运行多个 CLI session

#### Remote Control 功能

```
/remote on  → 开启远程控制
```

开启后：
- VSCode 把 session 历史、工具活动、状态更新**实时流式同步**到 GitHub 任务页面
- 你可以从 **github.com** 或 **GitHub Mobile App** 远程：
  - ✅ 提交新 prompt（指导 Agent 方向）
  - ✅ 审批/拒绝权限请求
  - ✅ 审查/批准多步代码生成计划
  - ✅ 回答 Agent 的诊断问题
- 双向同步：一边操作，另一边实时反映

#### 使用步骤

```
1. VSCode 设置中启用：github.copilot.chat.cli.remote.enabled
2. 打开 Chat 视图（Ctrl+Cmd+I）
3. Session Target 下拉选 "Copilot CLI"
4. 输入 /remote on
5. 点 "Open on GitHub" 或手机扫二维码
6. 手机上就能远程控制了
```

#### 其他有用的命令

| 命令 | 说明 |
|------|------|
| `/remote` | 查看当前远程连接状态 |
| `/remote off` | 断开远程会话 |
| `/keep-alive` | 防止电脑休眠（长时间运行时） |
| `/compact` | 压缩长对话上下文 |
| `/yolo` | 自动审批所有工具调用 |

#### 优势

```
✓ 官方原生功能，零第三方依赖
✓ 用 GitHub Mobile App 控制，不需要额外 App
✓ 完整的 session 历史和上下文
✓ 双向同步，实时流式
✓ 支持 Worktree 隔离，不干扰主工作区
✓ 可以用自定义 Agent
✓ 支持从 Local Agent 无缝交接给 CLI
✓ 用 Copilot 订阅额度，不额外花钱
```

#### 限制

```
✗ 需要 GitHub 账号登录 VSCode 和手机
✗ 需要工作区映射到 GitHub 仓库
✗ CLI session 不能访问所有 VSCode 内置工具
✗ 不能使用扩展提供的工具
✗ MCP 服务器只支持不需要认证的本地 MCP
✗ 依赖 GitHub 服务可用性
```

#### 评估

```
推荐度：★★★★★（对你来说是最优解）

理由：
- 你本来就用 VSCode + Copilot，零迁移成本
- 官方原生功能，稳定可靠
- GitHub Mobile App 就是"手机客户端"
- 不需要阿里云、不需要飞书、不需要任何第三方
- 离开电脑时 Copilot CLI 继续跑，手机随时接管
```

### 10.2-10.4 第三方扩展（精简对比）

这些扩展的共同点是：**本质上都更接近“模型 API 桥接”，而不是“官方级远程 Agent 控制”**。

| 扩展 | 核心定位 | 优点 | 主要限制 | 推荐度 |
|------|----------|------|----------|--------|
| Copilot as Service (`MartyZhou.vscode-copilot-as-service`) | 把 Copilot 暴露为 OpenAI 兼容 API | 接入简单，支持部分附加能力 | 仍依赖 VSCode 运行；不是完整 Agent 远程控制能力 | ★★☆☆☆ |
| Copilot Bridge (`larsbaunwall/vscode-copilot-bridge`) | 本地 API 桥接（更保守） | localhost + Token，设计更收敛 | 仅本地可用；不能直接满足远程控制诉求 | ★★☆☆☆ |
| Remote Copilot (`remotevs.remote-copilot-vscode`) | 浏览器远程控制 Copilot | 上手门槛低 | 依赖第三方中转，安全与稳定性风险较高 | ★☆☆☆☆ |

#### 一句话结论

- 如果你要的是“手机远程接管 VSCode Agent 任务”，优先官方的 **Copilot CLI + Remote Control**。
- 如果你要的是“把 Copilot 当模型能力暴露给其他系统”，可考虑前两者（API 桥接场景）。
- 对于经过第三方中转的远控方案，默认谨慎，除非你能接受安全边界和可用性风险。

## 十一、VSCode + Copilot 方案总结

### 最终结论（精简）

- 主力方案：**Copilot CLI + Remote Control**（官方原生，优先级最高）。
- 第三方扩展（Copilot as Service / Copilot Bridge）定位更偏向“模型 API 桥接”，不等价于远程 Agent 控制。
- 第三方中转型远控方案默认谨慎，只有在你明确接受安全边界和可用性风险时再考虑。

### 建议的落地顺序

1. 日常短时离开：直接用 Copilot CLI + `/remote on` + GitHub Mobile。
2. 复杂任务或长时间无人值守：用 OpenCode + 飞书桥接作为补充方案。
3. 需要系统集成时：再评估 API 桥接类扩展，不建议把它们当主远控方案。

## 十二、相关链接

### OpenCode 生态
- OpenCode 官网：https://opencode.ai
- OpenCode 文档：https://opencode.ai/docs
- OpenCode Server API：https://opencode.ai/docs/server/
- lark-opencode-bridge：https://github.com/YMaxwellHayes/lark-opencode-bridge
- golembot：https://github.com/0xranx/golembot
- opencode-remote-android：https://github.com/giuliastro/opencode-remote-android
- opencode-telegram-bot：https://github.com/grinev/opencode-telegram-bot

### VSCode + Copilot 生态
- Copilot CLI 官方文档：https://code.visualstudio.com/docs/agents/agent-types/copilot-cli
- Copilot CLI 连接 VSCode：https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/connecting-vs-code
- Remote Agent Sessions：https://code.visualstudio.com/docs/agents/remote-agent-sessions
- Copilot as Service 扩展：https://marketplace.visualstudio.com/items?itemName=MartyZhou.vscode-copilot-as-service
- Copilot Bridge 扩展：https://marketplace.visualstudio.com/items?itemName=thinkability.copilot-bridge（GitHub: https://github.com/larsbaunwall/vscode-copilot-bridge）
- Remote Copilot 扩展：https://marketplace.visualstudio.com/items?itemName=remotevs.remote-copilot-vscode

### OpenSpec 工作流
- OpenSpec：https://github.com/Fission-AI/OpenSpec
