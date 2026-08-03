#!/usr/bin/env bash
# 把 SPM 编译出的 binary 打包成 .app bundle，放进 /Applications
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="Clamshell Mode"
BUNDLE_ID="com.kriswonka.clamshellmode"
APP_DIR="/Applications/${APP_NAME}.app"

echo "→ swift build -c release"
swift build -c release

BIN_PATH=".build/arm64-apple-macosx/release/ClamshellModeApp"
[ -f "$BIN_PATH" ] || BIN_PATH=".build/release/ClamshellModeApp"

echo "→ 创建 bundle 结构"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/ClamshellModeApp"

[ -f "AppIcon.icns" ] && cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClamshellModeApp</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# ad-hoc sign（不需要开发者证书，跑在自己的 Mac 上够了）
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "✅ 装好了：$APP_DIR"
echo "   Spotlight 搜「Clamshell Mode」打开"
