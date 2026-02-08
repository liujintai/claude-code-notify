#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Claude Code Notify - 一键安装脚本
# 为 Claude Code 添加智能通知功能
# ============================================================

INSTALL_DIR="$HOME/.claude/claude-notify"
SETTINGS_FILE="$HOME/.claude/settings.json"
REPO_URL="https://raw.githubusercontent.com/liujintai/claude-code-notify/main"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============================================================
# 1. 环境检查
# ============================================================
info "检查运行环境..."

if [[ "$(uname)" != "Darwin" ]]; then
    error "仅支持 macOS 系统"
fi

if ! command -v swift &>/dev/null; then
    error "未找到 Swift 编译器，请先安装 Xcode Command Line Tools: xcode-select --install"
fi

if ! command -v python3 &>/dev/null; then
    error "未找到 python3"
fi

if ! command -v iconutil &>/dev/null; then
    error "未找到 iconutil（macOS 系统自带，不应缺失）"
fi

ok "环境检查通过 (Swift $(swift --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'))"

# ============================================================
# 2. 准备工作目录
# ============================================================
info "准备安装目录..."

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "$INSTALL_DIR"

# 判断是本地安装还是远程安装
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/src/ClaudeNotify.swift" ]]; then
    # 本地安装（从 clone 的仓库）
    info "检测到本地源码，使用本地文件..."
    SRC_DIR="$SCRIPT_DIR/src"
else
    # 远程安装（curl | bash）
    info "下载源码..."
    SRC_DIR="$WORK_DIR/src"
    mkdir -p "$SRC_DIR"
    curl -fsSL "$REPO_URL/src/ClaudeNotify.swift" -o "$SRC_DIR/ClaudeNotify.swift"
    curl -fsSL "$REPO_URL/src/notify.py" -o "$SRC_DIR/notify.py"
    curl -fsSL "$REPO_URL/src/cc.jpg" -o "$SRC_DIR/cc.jpg"
    ok "源码下载完成"
fi

# ============================================================
# 3. 转换图标 (jpg → icns)
# ============================================================
info "转换应用图标..."

ICONSET_DIR="$WORK_DIR/cc.iconset"
mkdir -p "$ICONSET_DIR"

for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$SRC_DIR/cc.jpg" --out "$ICONSET_DIR/tmp_${size}.png" -s format png &>/dev/null
done

# 按 macOS iconset 命名规范重命名
cp "$ICONSET_DIR/tmp_16.png"   "$ICONSET_DIR/icon_16x16.png"
cp "$ICONSET_DIR/tmp_32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/tmp_32.png"   "$ICONSET_DIR/icon_32x32.png"
cp "$ICONSET_DIR/tmp_64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/tmp_128.png"  "$ICONSET_DIR/icon_128x128.png"
cp "$ICONSET_DIR/tmp_256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/tmp_256.png"  "$ICONSET_DIR/icon_256x256.png"
cp "$ICONSET_DIR/tmp_512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/tmp_512.png"  "$ICONSET_DIR/icon_512x512.png"
cp "$ICONSET_DIR/tmp_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
rm -f "$ICONSET_DIR"/tmp_*.png

iconutil -c icns "$ICONSET_DIR" -o "$WORK_DIR/AppIcon.icns"
ok "图标转换完成"

# ============================================================
# 4. 编译 Swift 通知工具
# ============================================================
info "编译 ClaudeNotify.app..."

APP_DIR="$INSTALL_DIR/ClaudeNotify.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 编译（自动适配当前 CPU 架构）
swiftc "$SRC_DIR/ClaudeNotify.swift" \
    -o "$APP_DIR/Contents/MacOS/ClaudeNotify" \
    -framework Cocoa \
    -framework UserNotifications \
    2>&1

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.claude.notify</string>
    <key>CFBundleName</key>
    <string>ClaudeNotify</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeNotify</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# 图标
cp "$WORK_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# 签名
codesign --force --sign - "$APP_DIR" 2>/dev/null

ok "编译完成并已签名"

# ============================================================
# 5. 安装 notify.py 和图标
# ============================================================
info "安装通知脚本..."

cp "$SRC_DIR/notify.py" "$INSTALL_DIR/notify.py"
cp "$SRC_DIR/cc.jpg" "$INSTALL_DIR/cc.jpg"
chmod +x "$INSTALL_DIR/notify.py"

ok "文件安装完成 → $INSTALL_DIR/"

# ============================================================
# 6. 配置 Claude Code Hooks
# ============================================================
info "配置 Claude Code hooks..."

HOOK_CMD='python3 $HOME/.claude/claude-notify/notify.py'

if [[ -f "$SETTINGS_FILE" ]]; then
    # 检查是否已有 hooks 配置
    if python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f:
    cfg = json.load(f)
hooks = cfg.get('hooks', {}).get('Stop', [])
for h in hooks:
    for hh in h.get('hooks', []):
        if 'claude-notify' in hh.get('command', ''):
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        ok "hooks 已存在，跳过配置"
    else
        # 合并 hooks 到已有配置
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    cfg = json.load(f)
hooks = cfg.setdefault('hooks', {})
stop = hooks.setdefault('Stop', [])
stop.append({
    'hooks': [{
        'type': 'command',
        'command': '$HOOK_CMD'
    }]
})
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
"
        ok "hooks 已写入 $SETTINGS_FILE"
    fi
else
    # 创建新的 settings.json
    python3 -c "
import json
cfg = {
    'hooks': {
        'Stop': [{
            'hooks': [{
                'type': 'command',
                'command': '$HOOK_CMD'
            }]
        }]
    }
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
"
    ok "已创建 $SETTINGS_FILE"
fi

# ============================================================
# 7. 发送测试通知（触发权限请求）
# ============================================================
info "发送测试通知（首次运行需要授权通知权限）..."

"$APP_DIR/Contents/MacOS/ClaudeNotify" \
    -title "Claude Code Notify" \
    -message "安装成功！通知功能已就绪。" &
NOTIFY_PID=$!

sleep 3
kill $NOTIFY_PID 2>/dev/null || true

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Claude Code Notify 安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  安装位置: $INSTALL_DIR/"
echo "  配置文件: $SETTINGS_FILE"
echo ""
echo "  新开一个 Claude Code 会话即可生效。"
echo "  Claude 每次回复结束后，会自动推送通知摘要。"
echo ""
echo -e "  ${YELLOW}提示: 如果没看到测试通知，请到${NC}"
echo -e "  ${YELLOW}系统设置 → 通知 → ClaudeNotify 中开启通知权限${NC}"
echo ""
