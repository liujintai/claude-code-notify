# Claude Code Notify

Claude Code 智能通知工具 —— 当 AI 完成回复时，自动推送桌面通知摘要。

![macOS](https://img.shields.io/badge/macOS-supported-brightgreen)
![Python 3](https://img.shields.io/badge/Python-3.8+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange)

## 功能

- Claude Code 每次回复结束后，自动发送 macOS 桌面通知
- 使用 Haiku 模型生成简短摘要（如"代码编写完成"、"Bug已修复"）
- 自定义应用图标，通知中心可识别
- 全局安装，一次配置所有项目生效

## 效果预览

当 Claude Code 完成一次回复后，你会收到类似这样的通知：

```
┌─────────────────────────────┐
│ 🟠 Claude Code              │
│ 代码编写完成                 │
└─────────────────────────────┘
```

## 系统要求

- macOS（支持 Apple Silicon 和 Intel）
- Python 3.8+
- Swift 编译器（Xcode Command Line Tools 自带）
- Claude Code CLI

## 安装

### 方式一：一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB/claude-code-notify/main/install.sh | bash
```

### 方式二：克隆仓库安装

```bash
git clone https://github.com/YOUR_GITHUB/claude-code-notify.git
cd claude-code-notify
bash install.sh
```

安装脚本会自动：

1. 编译 Swift 通知工具（适配当前 CPU 架构）
2. 转换应用图标
3. 安装到 `~/.claude/claude-notify/`
4. 配置 Claude Code 全局 hooks
5. 发送测试通知（首次需授权通知权限）

## 安装后

新开一个 Claude Code 会话即可生效。无需任何额外配置。

如果首次没有收到测试通知，请到 **系统设置 → 通知 → ClaudeNotify** 中开启通知权限。

## 工作原理

```
Claude Code 回复结束
       ↓
  Stop Hook 触发
       ↓
  notify.py 执行
       ↓
  提取最后一轮对话
       ↓
  调用 Haiku 生成摘要
       ↓
  ClaudeNotify.app 推送通知
```

1. Claude Code 的 Stop Hook 在每次回复结束时触发 `notify.py`
2. `notify.py` 从 transcript 文件中提取最后一轮用户问题和 AI 回答
3. 调用 Claude Haiku 生成 10 字以内的摘要
4. 通过自制的 `ClaudeNotify.app` 推送带自定义图标的 macOS 通知

## 文件结构

```
~/.claude/claude-notify/
├── notify.py               # 通知脚本
├── cc.jpg                  # 图标源文件
└── ClaudeNotify.app/       # Swift 通知工具
    └── Contents/
        ├── Info.plist
        ├── MacOS/ClaudeNotify
        └── Resources/AppIcon.icns
```

## 配置

### 调试模式

修改 `~/.claude/settings.json` 中的 hooks command，添加 `NOTIFY_DEBUG=1`：

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "NOTIFY_DEBUG=1 python3 $HOME/.claude/claude-notify/notify.py"
      }]
    }]
  }
}
```

调试日志写入 `~/.claude/notify_debug.log`。

### 自定义图标

替换 `~/.claude/claude-notify/cc.jpg` 后重新运行安装脚本即可。

### API 配置

通知脚本使用 Claude Code 会话中的环境变量调用 Haiku：

- `ANTHROPIC_BASE_URL` — API 基础地址（默认 `https://api.anthropic.com`）
- `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN` — API 密钥

无需额外配置，脚本会自动继承 Claude Code 的环境变量。

## 卸载

```bash
# 方式一：使用卸载脚本
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB/claude-code-notify/main/uninstall.sh | bash

# 方式二：手动卸载
rm -rf ~/.claude/claude-notify
# 然后手动编辑 ~/.claude/settings.json 删除 hooks 配置
```

## 常见问题

**Q: 安装后没有收到通知？**

A: 到 系统设置 → 通知 → ClaudeNotify 中确认通知权限已开启。

**Q: 通知内容一直是"任务已完成"？**

A: 可能是 Haiku API 调用失败。开启调试模式查看日志：`cat ~/.claude/notify_debug.log`

**Q: 支持 Linux 吗？**

A: notify.py 支持 Linux（通过 `notify-send`），但没有自定义图标功能。安装脚本目前仅支持 macOS。

## License

MIT
