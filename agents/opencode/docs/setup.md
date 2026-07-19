# 环境配置指南

本文档介绍如何在新电脑上从零搭建 OpenCode 远程控制环境。

环境配置分为两部分：
1. **通用依赖**：所有通道共享的基础环境
2. **通道专属配置**：根据你选择的通道，安装对应的桥接工具和凭证

## 第一部分：通用依赖

以下依赖与通道无关，所有方案都需要安装。

### 1. 安装 Node.js

从 [Node.js 官网](https://nodejs.org/) 下载 LTS 版本安装（建议 >= 20）。安装后验证：

```powershell
node -v
npm -v
```

### 2. 安装 opencode

```powershell
npm install -g opencode-ai
opencode --version
```

> 脚本实际调用的是 `opencode.exe`，路径为 `%APPDATA%\npm\node_modules\opencode-ai\bin\opencode.exe`。

### 验证通用依赖

```powershell
node -v
opencode --version
```

全部有输出后，通用环境已就绪。接下来根据你要使用的通道，完成对应的专属配置。

---

## 第二部分：通道专属配置

根据你要使用的通道，选择对应的配置步骤。

### 飞书（Feishu）

#### 安装 Bun

Bun 是 opencode-lark 的运行环境。在 PowerShell 中执行：

```powershell
powershell -c "irm bun.sh/install.ps1 | iex"
```

安装后验证（默认装在 `~/.bun/bin`）：

```powershell
bun --version
```

> 如果 `bun` 命令找不到，把 `C:\Users\<你的用户名>\.bun\bin` 加到系统 PATH。

#### 安装 opencode-lark

```powershell
bun add -g opencode-lark
```

安装后验证：

```powershell
opencode-lark --version
```

> 实际二进制在 `~/.bun/bin/opencode-lark.exe`。

#### 配置飞书应用凭证

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

> 更详细的飞书应用创建指南请参考 [飞书配置指南](../../../docs/feishu-setup.md)。

#### 验证飞书通道环境

```powershell
opencode-lark --version
```

### Telegram

> 🔜 待补充

---

## 下一步

环境配置完成后，参考对应通道的文档启动远程控制：

- [飞书通道文档](../feishu/README.md)
