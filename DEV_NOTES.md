# clamshell-mode-mac — DEV NOTES

> 跨工具/跨会话的项目状态文档。AI 会话开始前先读这里。

**Last sync**: 2026-08-03 — Bark 提醒迁移（删 iMessage/SSH 整套）+ 贝壳 App 图标 + 光标修复收编进 main + install.sh 幂等修复；已部署同步并 push GitHub。

## 项目概览

macOS「合盖不睡眠」工具：Hammerspoon（`clamshell.lua`，菜单栏切换 + 合盖调暗/开盖渐亮）+ `setbrightness`（Swift，DisplayServices 私有 API）+ **Clamshell Mode.app**（SwiftUI 配置 GUI，SPM 构建，贝壳图标）。配置源：`~/.hammerspoon/clamshell-config.json`（App 写，lua 读）。**本目录是 git 仓库**（main，origin = GitHub KrisWonka/clamshell-mode-mac）；运行时部署 `~/.hammerspoon/` 与 main 一致（2026-08-03 同步）。

## 当前功能状态

- **Bark 长时间合盖提醒（2026-08-03，替代 iMessage）**：Settings 页分区 = 启用开关 + device key + 延时阈值 + 「发送测试推送」按钮（URLSession 直连当场验证）。lua 侧 `sendBark` 用 `hs.http.asyncGet` 请求 `https://api.day.app/<barkKey>/Clamshell Mode/<正文>`（逐段 URL 编码），key 为空不推。**iPhone-SSH 远程切换整套已删**（Setup 页只剩 Hammerspoon/sudoers 状态检查）。真机验证过：测试推送 iPhone 收到 ✓。用户当前 `notifyEnabled: false`（key 已配好，开关没开）。
- **App 图标（2026-08-03）**：贝壳 + 发光缝隙，深海夜蓝配色。母版 `app/AppIcon.svg` → `app/AppIcon.icns`（都进仓库），build-app.sh 拷入 bundle + `CFBundleIconFile`。改图标流程：改 SVG → headless Chrome 渲染 1024 PNG → sips 缩全尺寸 → iconutil。
- **光标/WindowServer 修复（2026-08-03 从孤本收编进 main）**：`refreshMenu(force)` + `lastSleepDisabled` 缓存（只在状态变化时重设菜单栏项）；菜单栏自刷新与盖子轮询解耦，`menuRefreshInterval or 15` 秒（lua-only 可选键，不进 GUI）。
- **系统亮屏时间分区（2026-07-30）**：3 个档位 Picker（屏保启动 / 电池关屏 / 电源关屏），系统即读即写不进 config JSON，E2E 验证过。
- 单测 18 个（15 ScreenTimers + 3 Config 解码迁移），`swift test` 全绿。

## 关键事实 / 陷阱

- **ClamshellConfig 解码是全字段 decodeIfPresent + 默认兜底**（extension 里的自定义 `init(from:)`，必须放 extension 否则 memberwise init 丢失）。以后加配置字段不会再触发"老 JSON 整体解码失败回退默认"。
- **install.sh 幂等坑（2026-08-03 修复）**：`grep -qF "$MARKER"` 的 MARKER 以 `--` 开头会被 BSD grep 当长选项 → 检查恒失败 → 每跑一次就往 init.lua 重复追加 require 块。现改为直接检查 `require("clamshell")` 字符串。
- sudoers 规则（`/etc/sudoers.d/clamshell-mode-pmset`）放行**整个** `/usr/bin/pmset`。
- **macOS 27 beta**：锁定屏幕设置已删屏保计时器 UI，但底层仍读 `com.apple.screensaver idleTime`；屏保由 WallpaperAerialsExtension 渲染（`pgrep ScreenSaverEngine` 假阴性）。`idleTime` 键不存在 = 默认 20 分钟。
- SwiftUI App 关窗即退出；SourceKit/LSP 对本 SPM 工程大量假阳性（以 `swift build`/`swift test` 为准）；`SystemInfo.runShell` 只回传 stdout（写命令成败用 `&& echo __OK__` 判定）。
- 有刘海的 Mac 菜单栏排不下会吞掉最左图标，且 Hammerspoon 报的 frame 不反映刘海遮挡；`HIDE_HS_MENUICON=1 ./install.sh` 可隐藏 HS 锤子腾 ~30px。

## 常用命令（都在本机 Mac 上跑）

```bash
cd ~/Documents/clamshell/app && swift test          # 单测
cd ~/Documents/clamshell && ./install.sh            # 全量部署（幂等）
diff ~/Documents/clamshell/clamshell.lua ~/.hammerspoon/clamshell.lua  # 核对 runtime == repo
```

## Open items

- **朋友机器待升级**（tsc@100.100.15.127，Tailscale，密码认证走 keyboard-interactive 且偶发抖动；sudo 要密码）：仍是旧 Bark(barkURL) 孤本版 + phone 字段 config。升级 = `git pull` + `./install.sh`；config 会被保留，需在 GUI 重填 barkKey。
- **旧克隆 `~/clamshell-mode-mac` 可清理**：其分支 `fix/menubar-refresh-window-storm` 的光标修复已收编进 main（2026-08-03），无孤本价值。
- `~/.hammerspoon/backup-20260803-052548/` 是 2026-08-03 交接前的运行时备份，确认稳定后可删。

## 设计文档

- Spec: `docs/superpowers/specs/2026-07-31-bark-notify-icon-design.md`（Bark/SSH/图标，含 08-03 增补）
- Plan: `docs/superpowers/plans/2026-08-03-bark-icon-ssh-removal.md`
- 上一轮: `specs/2026-07-30-system-screen-timers-design.md` + `plans/2026-07-30-system-screen-timers.md`
