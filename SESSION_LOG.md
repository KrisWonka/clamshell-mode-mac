# SESSION LOG

## 2026-08-03 — Bark 提醒迁移 + SSH 移除 + 贝壳图标 + 孤本修复收编

- iMessage 提醒 → **Bark**（config `phone`→`barkKey`，Config 解码改全字段 decodeIfPresent 容错；lua `sendBark`；GUI 分区带测试推送按钮，真机验证 iPhone 收到 ✓）；iPhone-SSH 远程切换整套删除（SetupView 两卡片 + SystemInfo 六函数 + README 整节）。
- 收编交接文档指出的孤本：光标/WindowServer 修复（`lastSleepDisabled` 缓存 + 菜单栏 15 秒自刷新解耦）从未推分支/部署版转正进 main。
- 新增贝壳 App 图标（`app/AppIcon.svg`/`.icns`，深海夜蓝，用户三选一定稿），build-app.sh 接线 CFBundleIconFile。
- 顺手修了 install.sh 幂等 bug（MARKER 以 `--` 开头被 BSD grep 当长选项 → init.lua 重复追加 require；改为检查 `require("clamshell")`，重跑实证幂等）。
- 部署同步完成（runtime == repo），单测 18/18。DEV_NOTES 过期的"非 git 仓库"表述已修正。
- 待办：朋友机器（tsc@100.100.15.127）待 git pull + install.sh 升级；旧克隆 ~/clamshell-mode-mac 可清理；用户 notifyEnabled 目前为关。

## 2026-07-30 23:18 — 系统亮屏时间设置区（3 个锁屏闲置计时器进 GUI）

- 新增 `ScreenTimers.swift`（模型 + pmset/defaults 读写，15 单测）+ SettingsView 顶部新分区（3 档位 Picker）+ Package.swift test target + README 中英各一行；App 已重新编译装进 /Applications。
- 为什么：用户想不开系统设置直接在自己 App 里调「屏幕多久不熄」的 3 个系统闲置计时器；方案定为系统即读即写（系统 = 唯一数据源，不进 config JSON，避免两边打架）。
- 验证：三个计时器全部 GUI→系统全链路实测通过；发现 macOS 27 beta 删了屏保计时器的系统设置 UI 但 idleTime 仍生效（屏保真实触发，由 WallpaperAerials 渲染）。系统值已还原基线（电池 10 分钟 / 电源永不 / 屏保 20 分钟）。
- 待办：无改动保存的 GUI sanity check（被锁屏打断，有单测兜底）；目录仍非 git 仓库。
