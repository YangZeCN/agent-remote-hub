# 环境配置指南

本文档介绍如何在新电脑上从零搭建 OpenCode 远程控制环境。

## 前置条件

- Node.js + npm
- Bun（opencode-lark 依赖）
- opencode（AI 引擎）
- opencode-lark（飞书桥接）
- 飞书应用凭证（App ID + App Secret）

## 安装步骤

### 1. 安装 Node.js

从 [Node.js 官网](https://nodejs.org/) 下载 LTS 版本安装（建议 >= 20）。安装后验证：

```powershell
node -v
npm -v
```

### 2. 安装 Bun

Bun 是 opencode-lark 的运行环境。在 PowerShell 中执行：

```powershell
powershell -c "irm bun.sh/install.ps1 | iex"
```

安装后验证（默认装在 `~/.bun/bin`）：

```powershell
bun --version
```

> 如果 `bun` 命令找不到，把 `C:\Users\<你的用户名>\.bun\bin` 加到系统 PATH。

### 3. 安装 opencode

```powershell
npm install -g opencode-ai
opencode --version
```

> 脚本实际调用的是 `opencode.exe`，路径为 `%APPDATA%\npm\node_modules\opencode-ai\bin\opencode.exe`。

### 4. 安装 opencode-lark

```powershell
bun add -g opencode-lark
```

安装后验证：

```powershell
opencode-lark --version
```

> 实际二进制在 `~/.bun/bin/opencode-lark.exe`。

### 5. 配置飞书应用凭证

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

### 6. 验证环境

```powershell
# 检查所有依赖
node -v
bun --version
opencode --version
opencode-lark --version
```

全部有输出后，就可以运行一键启动脚本了。

## 下一步

环境配置完成后，参考 [飞书通道文档](../feishu/README.md) 启动远程控制。
