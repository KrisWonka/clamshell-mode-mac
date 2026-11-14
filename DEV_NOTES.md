# clamshell-mode-mac — DEV NOTES

> 跨工具/跨会话的项目状态文档。AI 会话开始前先读这里。

**Last sync**: 2026-11-13 — 新增合盖省电两个开关（合盖即关屏 / 合盖期间低电量模式）+ GUI 改成单页（取消三个标签）+ 修 build-app.sh 装旧二进制的问题；已部署并 push GitHub。

## 项目概览

macOS「合盖不睡眠」工具：Hammerspoon（`clamshell.lua`，菜单栏切换 + 合盖调暗/开盖渐亮）+ `setbrightness`（Swift，DisplayServices 私有 API）+ **Clamshell Mode.app**（SwiftUI 配置 GUI，SPM 构建，贝壳图标）。配置源：`~/.hammerspoon/clamshell-config.json`（App 写，lua 读）。**本目录是 git 仓库**（main，origin = GitHub KrisWonka/clamshell-mode-mac）；运行时部署 `~/.hammerspoon/` 与 main 一致（2026-08-03 同步）。

## 当前功能状态

- **合盖省电（2026-11-13）**：两个开关 `lidCloseDisplaySleep` / `lidCloseLowPower`，代码默认关，用户本机已开。唤醒模式下合盖时：①`pmset displaysleepnow` 立即关屏（屏幕休眠 ≠ 系统睡眠，程序照跑；按系统设置会锁屏）；合盖期间屏幕被唤醒后，输入空闲满 60 秒再关一次（`hs.caffeinate.watcher` + `hs.host.idleTime()`，解决接电源时关屏计时为「永不」的情况）；②把电池/电源两段的能耗模式都切到 1，开盖恢复原值（键名 `powermode` 或 `lowpowermode` 按机型从 `pmset -g custom` 读）。合盖现场（亮度、能耗模式）落盘在 `~/.hammerspoon/clamshell-lid-state.json`，Hammerspoon 合盖期间重载/崩溃后开盖仍能恢复；启动时发现残留状态且盖子开着会补恢复。**真实合盖路径尚未实测。**
- **单页界面（2026-11-13）**：取消 Setup/Settings/About 三个标签。`ContentView` 只放 `SettingsView`；原 Setup 的两项状态检查成了页面顶部的「系统状态」分区；About 是标题栏左侧 ⓘ 按钮弹出的小面板。`SetupView.swift` 已删。
- **Bark 长时间合盖提醒（2026-08-03，替代 iMessage）**：Settings 页分区 = 启用开关 + device key + 延时阈值 + 「发送测试推送」按钮（URLSession 直连当场验证）。lua 侧 `sendBark` 用 `hs.http.asyncGet` 请求 `https://api.day.app/<barkKey>/Clamshell Mode/<正文>`（逐段 URL 编码），key 为空不推。**iPhone-SSH 远程切换整套已删**。真机验证过：测试推送 iPhone 收到 ✓。用户当前 `notifyEnabled: false`（key 已配好，开关没开）。
- **App 图标（2026-08-03）**：贝壳 + 发光缝隙，深海夜蓝配色。母版 `app/AppIcon.svg` → `app/AppIcon.icns`（都进仓库），build-app.sh 拷入 bundle + `CFBundleIconFile`。改图标流程：改 SVG → headless Chrome 渲染 1024 PNG → sips 缩全尺寸 → iconutil。
- **光标/WindowServer 修复（2026-08-03 从孤本收编进 main）**：`refreshMenu(force)` + `lastSleepDisabled` 缓存（只在状态变化时重设菜单栏项）；菜单栏自刷新与盖子轮询解耦，`menuRefreshInterval or 15` 秒（lua-only 可选键，不进 GUI）。
- **系统亮屏时间分区（2026-07-30）**：3 个档位 Picker（屏保启动 / 电池关屏 / 电源关屏），系统即读即写不进 config JSON，E2E 验证过。
- 单测 19 个（15 ScreenTimers + 4 Config），`swift test` 全绿。

## 关键事实 / 陷阱

- **build-app.sh 的产物路径必须问工具链**（2026-11-13 修复）：Swift 6.4 的新构建系统把产物放在 `.build/out/Products/Release/`，旧的 `.build/arm64-apple-macosx/release/` 下会留着过期二进制。脚本原先写死旧路径，于是 `swift build` 报成功、装进 App 的却是 8 月的文件。现用 `swift build -c release --show-bin-path`。排查这类"改了代码界面没变"先比对二进制修改时间，并确认旧进程真的退了（AppleScript 里这个 App 叫 `Clamshell Mode`，不是进程名 `ClamshellModeApp`）。
- **合盖后的耗电大头是显示链路**（2026-11-13 实测，开盖状态）：整机约 16–17 W，WindowServer 约 44% CPU、iTerm2 约 11%；`disablesleep` 下合盖系统仍认为屏幕开着，亮度 0 只灭背光。接电源时关屏计时是「永不」，20 分钟后屏保还会在合着的盖子下播放。
- **合盖省电实测（2026-11-13 22:08–23:54，电池供电，两个开关都开）**：合盖后关屏和低电量模式在同一秒生效（22:08:17），1 小时 47 分钟全程没有系统睡眠记录，开盖当秒（23:54:59）屏幕点亮、`powermode` 恢复 0/0、现场文件清除。「合盖期间屏幕被唤醒后再关一次」这条路径没被触发（期间屏幕没亮过），仍未验证。耗电约 7.8%/小时（约 5 W）；同一天下午没开这两项、屏幕靠 10 分钟闲置计时关闭的那次是约 5.1%/小时（约 3.5 W）——两次跑的东西不同，不能据此判断开关省了多少。核对办法：`pmset -g log` 看关屏/亮屏时刻，`/usr/bin/log show --predicate 'process == "powerd" AND category == "lowPowerMode"'` 看低电量模式切换，`eventMessage CONTAINS "capacity change"` 看每 1% 电量的时间点。zsh 里 `log` 是内建命令，必须写全路径 `/usr/bin/log`。
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

- **合盖省电到底省了多少，没有对照数据**：功能本身已实测通过（见上「合盖省电实测」），但 2026-11-13 两次合盖的负载不同，耗电数字不可比。要下结论需同一负载下开、关各合盖 30 分钟以上再比电量曲线。
- **朋友机器待升级**（tsc@100.100.15.127，Tailscale，密码认证走 keyboard-interactive 且偶发抖动；sudo 要密码）：仍是旧 Bark(barkURL) 孤本版 + phone 字段 config。升级 = `git pull` + `./install.sh`；config 会被保留，需在 GUI 重填 barkKey。
- **旧克隆 `~/clamshell-mode-mac` 可清理**：其分支 `fix/menubar-refresh-window-storm` 的光标修复已收编进 main（2026-08-03），无孤本价值。
- `~/.hammerspoon/backup-20260803-052548/` 是 2026-08-03 交接前的运行时备份，确认稳定后可删。

## 设计文档

- Spec: `docs/superpowers/specs/2026-07-31-bark-notify-icon-design.md`（Bark/SSH/图标，含 08-03 增补）
- Plan: `docs/superpowers/plans/2026-08-03-bark-icon-ssh-removal.md`
- 上一轮: `specs/2026-07-30-system-screen-timers-design.md` + `plans/2026-07-30-system-screen-timers.md`
