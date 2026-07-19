# 飞书应用创建指南

本文档介绍如何在飞书开放平台创建和配置应用，用于 OpenCode 远程控制。

## 方式 A：QR 扫码（推荐）

opencode-lark 支持扫码自动创建应用，这是最简单的方式。

### 步骤

1. 确保已安装 opencode-lark：
   ```powershell
   bun add -g opencode-lark
   ```

2. 运行 opencode-lark：
   ```powershell
   opencode-lark run
   ```

3. 首次运行会弹出二维码，用飞书扫码

4. 在飞书中确认应用创建授权

5. 扫码完成后，opencode-lark 会自动配置好应用凭证

### 优点

- 无需手动登录飞书开放平台
- 自动配置所有权限和能力
- 适合快速开始

### 注意事项

- 需要飞书管理员权限，或允许创建应用的组织
- 应用名称默认为 "opencode-lark"，可在飞书开放平台修改

## 方式 B：手动配置

如果需要更精细的控制，可以手动创建和配置应用。

### 1. 创建应用

1. 登录 [飞书开放平台](https://open.feishu.cn/)
2. 点击「创建应用」→「企业自建应用」
3. 填写应用信息：
   - **应用名称**：如 "OpenCode Assistant"
   - **应用描述**：如 "AI 编程助手远程控制"
   - **应用图标**：可选

### 2. 获取凭证

1. 进入应用详情页
2. 在「凭证与基础信息」页面获取：
   - **App ID**
   - **App Secret**

3. 保存凭证，后续需要配置到环境变量：
   ```powershell
   $env:LARK_APP_ID = "你的 App ID"
   $env:LARK_APP_SECRET = "你的 App Secret"
   ```

### 3. 开启机器人能力

1. 在应用详情页，点击「添加应用能力」
2. 选择「机器人」
3. 配置机器人信息：
   - **机器人名称**：如 "OpenCode"
   - **机器人描述**：如 "AI 编程助手"

### 4. 配置事件订阅

1. 在左侧菜单，点击「事件订阅」
2. 选择订阅方式：**WebSocket**（推荐）
   - WebSocket 模式无需公网 IP，适合本地开发
3. 添加以下事件：
   - `im.message.receive_v1`：接收消息
   - `im.message.message_read_v1`：消息已读（可选）

### 5. 配置权限

在「权限管理」页面，添加以下权限：

#### 必需权限

- `im:message`：获取与发送单聊、群组消息
- `im:message:send_as_bot`：以应用的身份发送消息
- `im:chat`：获取群组信息
- `im:resource`：获取消息中的资源文件

#### 可选权限

- `im:message.group_at_msg`：接收群聊中 @机器人消息
- `im:message.p2p_msg`：接收单聊消息

### 6. 发布应用

1. 在左侧菜单，点击「版本管理与发布」
2. 点击「创建版本」
3. 填写版本信息：
   - **版本号**：如 "1.0.0"
   - **更新说明**：如 "初始版本"
4. 点击「保存」→「申请发布」
5. 等待管理员审核（如果是管理员，可直接发布）

### 7. 测试应用

1. 在飞书中搜索机器人名称
2. 发送一条测试消息
3. 确认机器人能够正常响应

## 环境变量配置

### 临时配置（当前会话）

```powershell
$env:LARK_APP_ID = "cli_xxxxxxxxxx"
$env:LARK_APP_SECRET = "xxxxxxxxxxxxxxxxxxxxxxxx"
```

### 永久配置

#### 方式 1：系统环境变量

1. 右键「此电脑」→「属性」→「高级系统设置」
2. 点击「环境变量」
3. 在「用户变量」或「系统变量」中，点击「新建」
4. 添加：
   - 变量名：`LARK_APP_ID`
   - 变量值：你的 App ID
5. 重复步骤 4，添加 `LARK_APP_SECRET`

#### 方式 2：PowerShell Profile

1. 编辑 PowerShell 配置文件：
   ```powershell
   notepad $PROFILE
   ```

2. 添加以下内容：
   ```powershell
   $env:LARK_APP_ID = "cli_xxxxxxxxxx"
   $env:LARK_APP_SECRET = "xxxxxxxxxxxxxxxxxxxxxxxx"
   ```

3. 保存并重启 PowerShell

## 常见问题

### Q: 扫码创建应用失败？

**A**: 可能的原因：
- 你不是飞书管理员，或组织不允许创建应用
- 网络连接问题
- 飞书版本过旧

**解决方案**：
- 联系飞书管理员授权
- 改用手动配置方式

### Q: 机器人无法接收消息？

**A**: 检查以下几点：
1. 应用是否已发布并审核通过
2. 是否已开启机器人能力
3. 是否已添加 `im.message.receive_v1` 事件订阅
4. 是否已添加 `im:message` 等必需权限
5. WebSocket 连接是否正常（查看 opencode-lark 日志）

### Q: 如何查看应用日志？

**A**: opencode-lark 会将日志输出到标准输出：
```powershell
# 查看实时日志
Get-Content "$env:TEMP\opencode-lark-stdout.log" -Tail 20 -Wait

# 查看错误日志
Get-Content "$env:TEMP\opencode-lark-stderr.log" -Tail 20 -Wait
```

### Q: 多个飞书群聊如何配置？

**A**: opencode-lark 支持多个群聊，无需额外配置：
- 将机器人添加到多个群聊
- 每个群聊会自动创建独立的 session
- 会话映射存储在 `sessions.db` 中

### Q: 如何修改应用名称或图标？

**A**: 
1. 登录 [飞书开放平台](https://open.feishu.cn/)
2. 进入应用详情页
3. 在「基础信息」中修改名称、描述、图标
4. 重新发布应用版本

## 安全建议

1. **保护 App Secret**：不要将 App Secret 提交到代码仓库
2. **使用环境变量**：通过环境变量传递凭证，而非硬编码
3. **限制权限范围**：只添加必需的权限，避免过度授权
4. **定期轮换凭证**：如有安全顾虑，可重新生成 App Secret

## 相关链接

- [飞书开放平台文档](https://open.feishu.cn/document)
- [飞书机器人开发指南](https://open.feishu.cn/document/home/develop-a-bot)
- [opencode-lark 项目](https://github.com/guazi04/opencode-lark)
