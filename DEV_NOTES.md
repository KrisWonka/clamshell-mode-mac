# clamshell-mode-mac — DEV NOTES

> 跨工具/跨会话的项目状态文档。AI 会话开始前先读这里。

**Last sync**: 2026-07-30 23:18 — 新增「系统亮屏时间」设置区：macOS 锁屏的 3 个闲置计时器进了 GUI，端到端验证通过。

## 项目概览

macOS「合盖不睡眠」工具：Hammerspoon（`clamshell.lua`，菜单栏切换 + 合盖调暗/开盖渐亮）+ `setbrightness`（Swift，DisplayServices 私有 API）+ **Clamshell Mode.app**（SwiftUI 配置 GUI，SPM 构建）。配置源：`~/.hammerspoon/clamshell-config.json`（App 写，lua 读）。GitHub: KrisWonka/clamshell-mode-mac；**本目录当前不是 git 仓库**（无 .git，改动只落盘）。

## 当前功能状态

- **系统亮屏时间分区（2026-07-30 新增）**：Settings 页顶部，3 个档位 Picker——启动屏幕保护程序 / 电池供电关闭显示器 / 接通电源关闭显示器。
  - 数据源 = 系统本身（`pmset -g custom` + `defaults -currentHost read com.apple.screensaver idleTime`），**不进 config JSON**；保存时只写 diff 出的改动项（`sudo -n pmset -b/-c displaysleep N`、`defaults ... idleTime -int 秒`），写完回读回显。
  - 实现：`app/Sources/ClamshellModeApp/ScreenTimers.swift`（纯函数 + runner 可注入的 IO）+ `SettingsView.swift` 接线。
  - 单测：`app/Tests/ClamshellModeAppTests/ScreenTimersTests.swift`，15 个，`swift test` 全绿。
  - E2E 已验证（GUI 点击→保存→命令行核对）：AC 永不↔1min ✓、电池 10↔15min ✓、屏保 20→5→1min ✓ 且屏保真实触发 ✓。
- 其余功能（合盖模式切换、渐亮、iMessage 提醒、快捷键、图标）不变；三个旧时间参数（fadeDuration / pollInterval / notifyDelaySec）仍在 config JSON。

## 关键事实 / 陷阱

- sudoers 规则（`/etc/sudoers.d/clamshell-mode-pmset`）放行**整个** `/usr/bin/pmset`，所以 displaysleep 写入天然免密，install.sh 无需变更。
- **macOS 27 beta（用户当前系统）**：系统设置→锁定屏幕已**删除**屏保计时器 UI（只剩两个关屏时间），但底层仍读 `com.apple.screensaver idleTime`（-currentHost，秒）。屏保由 WallpaperAerialsExtension 渲染，**不是** ScreenSaverEngine——用 `pgrep ScreenSaverEngine` 检测会假阴性。
- `idleTime` 键不存在 = 系统默认 20 分钟（App 按 20 显示）。
- SwiftUI App 关窗即退出（`applicationShouldTerminateAfterLastWindowClosed = true`）。
- SourceKit/LSP 对这个 SPM 工程报大量假阳性诊断（No such module XCTest / Cannot find type ...）——以 `swift build` / `swift test` 为准。
- `SystemInfo.runShell` 只回传 stdout、拿不到退出码 → 写命令成败用 `&& echo __OK__` 判定（ScreenTimersIO.apply 的约定）。

## 常用命令（都在本机 Mac 上跑）

```bash
cd ~/Documents/clamshell/app && swift test          # 单测
cd ~/Documents/clamshell/app && bash build-app.sh   # 编译并装到 /Applications
pmset -g custom | grep displaysleep                 # 核对关屏时间
defaults -currentHost read com.apple.screensaver idleTime   # 核对屏保秒数
```

## Open items

- 「无改动保存不写系统」的 GUI 实测被锁屏打断未跑（有单测 `testApplyNoChangesRunsNothing` 覆盖）；下次开 App 顺手点一次保存核对即可。
- 目录不是 git 仓库——若要推回 GitHub，需要用户决定如何接回（clone 后拷贝或 git init + remote）。

## 设计文档

- Spec: `docs/superpowers/specs/2026-07-30-system-screen-timers-design.md`
- Plan: `docs/superpowers/plans/2026-07-30-system-screen-timers.md`
