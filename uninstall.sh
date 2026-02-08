#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Claude Code Notify - 卸载脚本
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

INSTALL_DIR="$HOME/.claude/claude-notify"
SETTINGS_FILE="$HOME/.claude/settings.json"

# 1. 删除安装目录
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "已删除 $INSTALL_DIR"
else
    info "安装目录不存在，跳过"
fi

# 2. 从 settings.json 中移除 hooks
if [[ -f "$SETTINGS_FILE" ]]; then
    python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    cfg = json.load(f)
hooks = cfg.get('hooks', {})
stop = hooks.get('Stop', [])
stop = [h for h in stop if not any('claude-notify' in hh.get('command', '') for hh in h.get('hooks', []))]
if stop:
    hooks['Stop'] = stop
else:
    hooks.pop('Stop', None)
if not hooks:
    cfg.pop('hooks', None)
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
"
    ok "已从 $SETTINGS_FILE 中移除 hooks 配置"
fi

# 3. 清理日志
if [[ -f "$HOME/.claude/notify_debug.log" ]]; then
    rm -f "$HOME/.claude/notify_debug.log"
    ok "已清理调试日志"
fi

echo ""
echo -e "${GREEN}Claude Code Notify 已卸载完成。${NC}"
echo ""
