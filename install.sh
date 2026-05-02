#!/usr/bin/env bash
# clamshell-mode-mac installer
# - 编译 setbrightness Swift 工具
# - 配置 pmset 免密 sudo
# - 拷 clamshell.lua + 默认菜单栏图标 + 默认 config.json 到 ~/.hammerspoon/
# - 在 init.lua 里 require("clamshell")
# - 编译并安装 Clamshell Mode.app GUI
# - 重载 Hammerspoon

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"
MARKER='-- clamshell-mode-mac (installed by install.sh)'
CONFIG_JSON="$HS_DIR/clamshell-config.json"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }

# 1. 平台 + 依赖
[[ "$(uname)" == "Darwin" ]] || { red "仅支持 macOS"; exit 1; }
[ -d "/Applications/Hammerspoon.app" ] || { red "未检测到 Hammerspoon。请先安装：brew install --cask hammerspoon"; exit 1; }
command -v swiftc >/dev/null || { red "未检测到 swiftc。请安装 Xcode Command Line Tools：xcode-select --install"; exit 1; }

mkdir -p "$HS_DIR"

# 2. 编译 setbrightness
bold "编译 setbrightness…"
swiftc "$REPO_DIR/setbrightness.swift" \
  -framework CoreGraphics \
  -F /System/Library/PrivateFrameworks \
  -framework DisplayServices \
  -o "$HS_DIR/setbrightness"
green "  -> $HS_DIR/setbrightness"

# 3. pmset 免密 sudo
SUDOERS_FILE="/etc/sudoers.d/clamshell-mode-pmset"
if sudo -n /usr/bin/pmset -g >/dev/null 2>&1; then
  green "pmset 已可免密 sudo，跳过 sudoers 配置"
else
  bold "配置 pmset 免密 sudo（需要你的密码）…"
  TMP_FILE="$(mktemp)"
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pmset" > "$TMP_FILE"
  sudo install -m 440 -o root -g wheel "$TMP_FILE" "$SUDOERS_FILE"
  sudo visudo -c -f "$SUDOERS_FILE" >/dev/null
  rm -f "$TMP_FILE"
  green "  -> $SUDOERS_FILE"
fi

# 4. 拷贝 lua + 菜单栏图标
install -m 644 "$REPO_DIR/clamshell.lua" "$HS_DIR/clamshell.lua"
install -m 644 "$REPO_DIR/icon-sleep.png" "$HS_DIR/icon-sleep.png"
install -m 644 "$REPO_DIR/icon-awake.png" "$HS_DIR/icon-awake.png"
green "已拷贝 clamshell.lua + 默认菜单栏图标"

# 5. 写默认 config.json（已存在则跳过，保留用户配置）
if [ -f "$CONFIG_JSON" ]; then
  green "$CONFIG_JSON 已存在，保留现有配置"
else
  cat > "$CONFIG_JSON" <<'EOF'
{
  "fadeDuration" : 1.5,
  "fadeEnabled" : true,
  "hotkeyEnabled" : true,
  "hotkeyKey" : "6",
  "hotkeyMods" : [
    "ctrl",
    "alt",
    "cmd"
  ],
  "iconAwake" : "cup.and.saucer.fill",
  "iconSleep" : "zzz",
  "notifyDelaySec" : 900,
  "notifyEnabled" : false,
  "phone" : "",
  "pollInterval" : 1
}
EOF
  green "  -> $CONFIG_JSON（默认配置，可在 GUI 里改）"
fi

# 6. 在 init.lua 里 require（幂等）
touch "$INIT_LUA"
if grep -qF "$MARKER" "$INIT_LUA"; then
  green "init.lua 已包含 clamshell-mode-mac，跳过追加"
else
  bold "追加 require 到 init.lua…"
  {
    echo ""
    echo "$MARKER"
    echo 'require("clamshell")'
  } >> "$INIT_LUA"
  green "  -> 已追加"
fi

# 7. 编译并安装 Clamshell Mode.app
if [ -d "$REPO_DIR/app" ]; then
  bold "编译 Clamshell Mode.app（GUI 配置面板）…"
  if (cd "$REPO_DIR/app" && bash build-app.sh) >/dev/null 2>&1; then
    green "  -> /Applications/Clamshell Mode.app"
  else
    red "  app 编译失败（命令行配置仍可用）"
  fi
fi

# 8. 重载 Hammerspoon
bold "重载 Hammerspoon…"
osascript -e 'quit app "Hammerspoon"' 2>/dev/null || true
sleep 1
open -a Hammerspoon
sleep 1
green "完成！"

cat <<EOF

下一步：
- 抬头看右上角菜单栏，应该有月亮 zzz 图标
- 点图标或按 ⌃⌥⌘+6 切换合盖不睡眠模式
- Spotlight 搜「Clamshell」打开 GUI 配置（手机号 / 快捷键 / 图标 / 时长等）

要卸载：./uninstall.sh
EOF
