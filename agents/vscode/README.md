# VSCode 远程控制方案

> ⚠️ 本方案尚在规划阶段，内容待补充。

## 目标

通过通信通道（飞书、Telegram 等）远程控制 VSCode 中的 AI 编程助手（如 Copilot Chat、Cline 等）。

## 当前状态

### 官方原生方案（已可用）

GitHub 官方已提供 **Copilot CLI + Remote Control** 功能，这是目前最推荐的方案：

- ✅ 官方原生功能，零第三方依赖
- ✅ 用 GitHub Mobile App 控制，不需要额外 App
- ✅ 完整的 session 历史和上下文
- ✅ 双向同步，实时流式
- ✅ 支持 Worktree 隔离，不干扰主工作区

**详细调研和使用步骤**：[VSCode 方案调研文档](docs/research.md)

### 自建通道方案（规划中）

如果官方方案无法满足需求，可以考虑自建飞书/Telegram 通道：

- **飞书（Feishu）**：通过飞书远程控制 VSCode
- **Telegram**：通过 Telegram 远程控制 VSCode

## 可能的技术路线

- **VSCode Extension**：开发专用扩展，暴露 HTTP API 供桥接服务调用
- **VSCode CLI / Tunnel**：利用 VSCode 的远程隧道能力
- **第三方工具集成**：对接现有远程控制方案

## 支持的通道（规划）

- [飞书（Feishu）](feishu/) - 企业级即时通讯
- [Telegram](telegram/) - 个人即时通讯

## 更新

本目录内容确定后会更新，欢迎提 Issue 讨论方案。
