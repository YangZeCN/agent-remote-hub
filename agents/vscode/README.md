# VSCode 远程控制方案（规划中）

> ⚠️ 本方案尚在规划阶段，内容待补充。

## 目标

通过通信通道（飞书、Telegram 等）远程控制 VSCode 中的 AI 编程助手（如 Copilot Chat、Cline 等）。

## 可能的技术路线

- **VSCode Extension**：开发专用扩展，暴露 HTTP API 供桥接服务调用
- **VSCode CLI / Tunnel**：利用 VSCode 的远程隧道能力
- **第三方工具集成**：对接现有远程控制方案

## 支持的通道（规划）

- [飞书（Feishu）](feishu/) - 企业级即时通讯
- [Telegram](telegram/) - 个人即时通讯

## 更新

本目录内容确定后会更新，欢迎提 Issue 讨论方案。
