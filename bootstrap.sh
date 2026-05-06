#!/usr/bin/env bash
# 一键引导：在全新 macOS 上装好 clamshell-mode-mac + fan-hotkey-mac
# 包含所有前置依赖（Xcode CLT / Homebrew / Hammerspoon / Macs Fan Control）
#
# 用法（在新 Mac 上）：
#   curl -fsSL https://raw.githubusercontent.com/KrisWonka/clamshell-mode-mac/main/bootstrap.sh | bash
# 或者克隆后本地运行：
#   ./bootstrap.sh

set -euo pipefail

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }

[[ "$(uname)" == "Darwin" ]] || { red "仅支持 macOS"; exit 1; }

WORKDIR="${WORKDIR:-$HOME}"
mkdir -p "$WORKDIR"

# ---- 1. Xcode Command Line Tools ----
if ! xcode-select -p >/dev/null 2>&1; then
  bold "[1/6] 安装 Xcode Command Line Tools（弹窗里点 Install，等装完即可继续）…"
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
  green "  -> CLT 就绪"
else
  green "[1/6] Xcode CLT 已装，跳过"
fi

# ---- 2. Homebrew ----
if ! command -v brew >/dev/null 2>&1; then
  bold "[2/6] 安装 Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ];   then eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  green "[2/6] Homebrew 已装，跳过"
  eval "$(brew shellenv)"
fi

# ---- 3. Hammerspoon + Macs Fan Control ----
bold "[3/6] 安装 Hammerspoon / Macs Fan Control…"
brew install --cask hammerspoon macs-fan-control

# ---- 4. 启动一次 Hammerspoon 申请 Accessibility 权限 ----
if ! pgrep -q Hammerspoon; then
  bold "[4/6] 首次启动 Hammerspoon — 弹窗里给「辅助功能 / Accessibility」权限…"
  open -ga Hammerspoon
  sleep 2
else
  green "[4/6] Hammerspoon 已在运行"
fi

# ---- 5. 拉取两个项目 ----
bold "[5/6] 拉取项目到 $WORKDIR …"
cd "$WORKDIR"
for repo in clamshell-mode-mac fan-hotkey-mac; do
  if [ -d "$repo/.git" ]; then
    (cd "$repo" && git pull --ff-only) || true
    green "  -> $repo 已在，已尝试更新"
  else
    git clone "https://github.com/KrisWonka/$repo.git"
    green "  -> 已 clone $repo"
  fi
done

# ---- 6. 跑两个 installer ----
bold "[6/6] 执行各项目自带 install.sh…"
( cd "$WORKDIR/clamshell-mode-mac" && ./install.sh )
( cd "$WORKDIR/fan-hotkey-mac"     && ./install.sh )

green ""
green "🎉 全部装好了"
cat <<EOF

下一步（新 Mac 上记得做）:
  - System Settings → Privacy & Security → Accessibility
    确认 Hammerspoon 是 ON（首次必须，否则快捷键不响应）
  - ⌃⌥⌘ + 6 切换「合盖不睡眠」
  - ⌃⌥⌘ + 8 切换 Macs Fan Control「全速 / Auto」
  - Spotlight 搜「Clamshell」/「Fan Hotkey」开各自 GUI 调设置
EOF
