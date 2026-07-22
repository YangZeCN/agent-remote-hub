# VSCode + GitHub Copilot 远程控制方案调研

> 调研日期：2026-07-22  
> 状态：已调研，官方原生功能可用

## 决策摘要

**主力方案**：Copilot CLI + Remote Control（官方原生，优先级最高）

如果你要的是"手机远程接管 VSCode Agent 任务"，优先官方的 **Copilot CLI + Remote Control**。这是 GitHub 官方提供的原生远程控制功能，2026 年 7 月文档显示已可用。

## Copilot CLI + Remote Control

### 是什么

Copilot CLI 是 VSCode 内置的后台 Agent 运行模式：
- Agent 在后台独立运行，不依赖 VSCode 窗口（关闭窗口也继续跑）
- 支持 Worktree 隔离（Git worktree，不干扰你的主工作区）
- 支持 Folder 模式（直接修改当前工作区）
- 可以并行运行多个 CLI session

### Remote Control 功能

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

### 使用步骤

```
1. VSCode 设置中启用：github.copilot.chat.cli.remote.enabled
2. 打开 Chat 视图（Ctrl+Cmd+I）
3. Session Target 下拉选 "Copilot CLI"
4. 输入 /remote on
5. 点 "Open on GitHub" 或手机扫二维码
6. 手机上就能远程控制了
```

### 其他有用的命令

| 命令 | 说明 |
|------|------|
| `/remote` | 查看当前远程连接状态 |
| `/remote off` | 断开远程会话 |
| `/keep-alive` | 防止电脑休眠（长时间运行时） |
| `/compact` | 压缩长对话上下文 |
| `/yolo` | 自动审批所有工具调用 |

### 优势

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

### 限制

```
✗ 需要 GitHub 账号登录 VSCode 和手机
✗ 需要工作区映射到 GitHub 仓库
✗ CLI session 不能访问所有 VSCode 内置工具
✗ 不能使用扩展提供的工具
✗ MCP 服务器只支持不需要认证的本地 MCP
✗ 依赖 GitHub 服务可用性
```

### 评估

```
推荐度：★★★★★（对主力使用 Copilot 的用户来说是最优解）

理由：
- 本来就用 VSCode + Copilot，零迁移成本
- 官方原生功能，稳定可靠
- GitHub Mobile App 就是"手机客户端"
- 不需要阿里云、不需要飞书、不需要任何第三方
- 离开电脑时 Copilot CLI 继续跑，手机随时接管
```

## 第三方扩展对比

这些扩展的共同点是：**本质上都更接近"模型 API 桥接"，而不是"官方级远程 Agent 控制"**。

| 扩展 | 核心定位 | 优点 | 主要限制 | 推荐度 |
|------|----------|------|----------|--------|
| Copilot as Service (`MartyZhou.vscode-copilot-as-service`) | 把 Copilot 暴露为 OpenAI 兼容 API | 接入简单，支持部分附加能力 | 仍依赖 VSCode 运行；不是完整 Agent 远程控制能力 | ★★☆☆☆ |
| Copilot Bridge (`larsbaunwall/vscode-copilot-bridge`) | 本地 API 桥接（更保守） | localhost + Token，设计更收敛 | 仅本地可用；不能直接满足远程控制诉求 | ★★☆☆☆ |
| Remote Copilot (`remotevs.remote-copilot-vscode`) | 浏览器远程控制 Copilot | 上手门槛低 | 依赖第三方中转，安全与稳定性风险较高 | ★☆☆☆☆ |

### 一句话结论

- 如果你要的是"手机远程接管 VSCode Agent 任务"，优先官方的 **Copilot CLI + Remote Control**。
- 如果你要的是"把 Copilot 当模型能力暴露给其他系统"，可考虑前两者（API 桥接场景）。
- 对于经过第三方中转的远控方案，默认谨慎，除非你能接受安全边界和可用性风险。

## 建议的落地顺序

1. 日常短时离开：直接用 Copilot CLI + `/remote on` + GitHub Mobile。
2. 复杂任务或长时间无人值守：用 OpenCode + 飞书/Telegram 桥接作为补充方案。
3. 需要系统集成时：再评估 API 桥接类扩展，不建议把它们当主远控方案。

## 相关链接

- Copilot CLI 官方文档：https://code.visualstudio.com/docs/agents/agent-types/copilot-cli
- Copilot CLI 连接 VSCode：https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/connecting-vs-code
- Remote Agent Sessions：https://code.visualstudio.com/docs/agents/remote-agent-sessions
- Copilot as Service 扩展：https://marketplace.visualstudio.com/items?itemName=MartyZhou.vscode-copilot-as-service
- Copilot Bridge 扩展：https://marketplace.visualstudio.com/items?itemName=thinkability.copilot-bridge
- Remote Copilot 扩展：https://marketplace.visualstudio.com/items?itemName=remotevs.remote-copilot-vscode
