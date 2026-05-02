#!/usr/bin/env bash
# clamshell-mode-mac uninstaller
# 反向操作 install.sh：删 lua / 二进制 / 图标 / config / sudoers / app，
# 并从 init.lua 里去掉 require("clamshell")

set -euo pipefail

HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"
MARKER='-- clamshell-mode-mac (installed by install.sh)'
SUDOERS_FILE="/etc/sudoers.d/clamshell-mode-pmset"
APP_DIR="/Applications/Clamshell Mode.app"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }

read -p "确定卸载 clamshell-mode-mac？(y/N) " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "取消"; exit 0; }

# 1. 删 ~/.hammerspoon 下的资产
bold "清理 $HS_DIR/…"
for f in setbrightness clamshell.lua clamshell-config.json icon-sleep.png icon-awake.png; do
  if [ -e "$HS_DIR/$f" ]; then
    rm -f "$HS_DIR/$f"
    green "  rm $f"
  fi
done

# 2. 从 init.lua 去掉 require
if [ -f "$INIT_LUA" ] && grep -qF "$MARKER" "$INIT_LUA"; then
  bold "从 init.lua 去掉 require…"
  # 删除 marker 行 + 紧随的 require("clamshell") 行 + 标记前的空行
  TMP="$(mktemp)"
  awk -v marker="$MARKER" '
    BEGIN { skip = 0 }
    {
      if ($0 == marker) { skip = 2; if (prev == "") prev_skipped = 1; next }
      if (skip > 0) { skip--; next }
      if (prev_skipped) { prev_skipped = 0; if ($0 == "") next }
      print prev
      prev = $0
    }
    END { if (!prev_skipped) print prev }
  ' "$INIT_LUA" | sed '1{/^$/d;}' > "$TMP"
  mv "$TMP" "$INIT_LUA"
  green "  done"
fi

# 3. sudoers
if [ -f "$SUDOERS_FILE" ]; then
  bold "删除 sudoers 规则（要密码）…"
  sudo rm -f "$SUDOERS_FILE"
  green "  rm $SUDOERS_FILE"
fi

# 4. /Applications/Clamshell Mode.app
if [ -d "$APP_DIR" ]; then
  bold "删 $APP_DIR…"
  rm -rf "$APP_DIR"
  green "  done"
fi

# 5. 重载 Hammerspoon
bold "重载 Hammerspoon…"
osascript -e 'quit app "Hammerspoon"' 2>/dev/null || true
sleep 1
open -a Hammerspoon 2>/dev/null || true

green "卸载完成。"
