# SESSION LOG

## 2026-07-30 23:18 — 系统亮屏时间设置区（3 个锁屏闲置计时器进 GUI）

- 新增 `ScreenTimers.swift`（模型 + pmset/defaults 读写，15 单测）+ SettingsView 顶部新分区（3 档位 Picker）+ Package.swift test target + README 中英各一行；App 已重新编译装进 /Applications。
- 为什么：用户想不开系统设置直接在自己 App 里调「屏幕多久不熄」的 3 个系统闲置计时器；方案定为系统即读即写（系统 = 唯一数据源，不进 config JSON，避免两边打架）。
- 验证：三个计时器全部 GUI→系统全链路实测通过；发现 macOS 27 beta 删了屏保计时器的系统设置 UI 但 idleTime 仍生效（屏保真实触发，由 WallpaperAerials 渲染）。系统值已还原基线（电池 10 分钟 / 电源永不 / 屏保 20 分钟）。
- 待办：无改动保存的 GUI sanity check（被锁屏打断，有单测兜底）；目录仍非 git 仓库。
