# SESSION LOG

## 2026-11-13 — 合盖省电两个开关 + 单页界面 + 构建脚本修复

- 起因：用户发现唤醒模式合盖后仍在全功率跑。只读采样确认大头是显示链路（WindowServer 约 44% CPU），不是后台 App。
- 新增两个开关（代码默认关，用户本机已开）：合盖即关屏、合盖期间低电量模式并在开盖恢复；合盖现场落盘防重载丢失。
- GUI 改成单页：三个标签取消，状态检查并入页面顶部，About 改成 ⓘ 小面板，删 `SetupView.swift`。
- 修 `build-app.sh`：新版 Swift 换了产物目录，脚本一直在装 8 月的旧二进制，改为 `--show-bin-path`。
- 合盖实测通过（22:08–23:54，电池）：关屏与低电量模式同一秒生效，全程无系统睡眠，开盖当秒恢复。耗电约 7.8%/小时，下午没开这两项时约 5.1%/小时，两次负载不同、不可比。
- 待办：省电量缺同负载对照；「屏幕被唤醒后再关」路径未触发过；朋友机器仍待升级。

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
