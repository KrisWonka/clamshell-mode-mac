#!/usr/bin/env bash
# clamshell-mode-mac installer
# - 编译 setbrightness Swift 工具
# - 配置 pmset 免密 sudo
# - 把 clamshell.lua 拷进 ~/.hammerspoon/ 并在 init.lua 里 require
# - 重载 Hammerspoon

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"
MARKER='-- clamshell-mode-mac (installed by install.sh)'

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }

# 1. 平台检查
[[ "$(uname)" == "Darwin" ]] || { red "仅支持 macOS"; exit 1; }

# 2. 依赖
if ! [ -d "/Applications/Hammerspoon.app" ]; then
  red "未检测到 Hammerspoon。请先安装：brew install --cask hammerspoon"
  exit 1
fi
command -v swiftc >/dev/null || { red "未检测到 swiftc。请安装 Xcode Command Line Tools：xcode-select --install"; exit 1; }

mkdir -p "$HS_DIR"

# 3. 编译 setbrightness
bold "编译 setbrightness…"
swiftc "$REPO_DIR/setbrightness.swift" \
  -framework CoreGraphics \
  -F /System/Library/PrivateFrameworks \
  -framework DisplayServices \
  -o "$HS_DIR/setbrightness"
green "  -> $HS_DIR/setbrightness"

# 4. pmset 免密 sudo
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

# 5. 拷贝 clamshell.lua
install -m 644 "$REPO_DIR/clamshell.lua" "$HS_DIR/clamshell.lua"
green "已拷贝 clamshell.lua → $HS_DIR/"

# 5b. 渲染默认菜单栏图标（SF Symbols → PNG）
RENDERER="$REPO_DIR/.build-renderer"
mkdir -p "$REPO_DIR/.build-cache"
cat > "$REPO_DIR/.build-cache/render.swift" <<'SWEOF'
import AppKit
let args = CommandLine.arguments
guard args.count == 3 else { exit(1) }
let symbol = args[1]
let outputPath = args[2]
let pointSize: CGFloat = 18
guard let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { exit(2) }
let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
let img = baseImg.withSymbolConfiguration(cfg) ?? baseImg
let scale: CGFloat = 2
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pointSize*scale), pixelsHigh: Int(pointSize*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else { exit(3) }
rep.size = NSSize(width: pointSize, height: pointSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.black.setFill()
img.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
SWEOF
swiftc "$REPO_DIR/.build-cache/render.swift" -o "$REPO_DIR/.build-cache/render" 2>/dev/null
"$REPO_DIR/.build-cache/render" "zzz" "$HS_DIR/icon-sleep.png"
"$REPO_DIR/.build-cache/render" "cup.and.saucer.fill" "$HS_DIR/icon-awake.png"
green "已生成菜单栏图标"

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

# 7. （可选）编译并安装 Clamshell Mode.app 配置 GUI
if [ -d "$REPO_DIR/app" ]; then
  bold "编译 Clamshell Mode.app（GUI 配置面板）…"
  if (cd "$REPO_DIR/app" && bash build-app.sh) >/dev/null 2>&1; then
    green "  -> /Applications/Clamshell Mode.app（Spotlight 搜「Clamshell」打开）"
  else
    red "  app 编译失败（可跳过，命令行配置一样能用）"
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
- 抬头看右上角菜单栏，应该有 💤 图标。
- 点 💤 切到 ☕️ 即「合盖不睡眠」模式；再点切回。
- 在 ☕️ 模式下合盖：屏幕亮度自动归 0；开盖：${FADE_DURATION:-1.5}s 平滑升回原亮度。

要卸载：
  rm $HS_DIR/setbrightness $HS_DIR/clamshell.lua
  sudo rm -f $SUDOERS_FILE
  在 init.lua 里删掉 'require("clamshell")' 那两行
  重载 Hammerspoon
EOF
