# 「系统亮屏时间」设置区 — 设计 spec

日期：2026-07-30
状态：已获用户批准（方案 A：系统即读即写）

## 背景与目标

macOS「锁定屏幕」设置里有 3 个决定屏幕多久不熄的闲置计时器。用户希望不开系统设置，直接在 Clamshell Mode.app 的 Settings 页里查看和修改它们：

1. **启动屏幕保护程序**（`defaults -currentHost` 域 `com.apple.screensaver`，键 `idleTime`，单位秒，0 = 永不；未设置时系统默认 20 分钟）
2. **电池供电时关闭显示器**（`pmset -b displaysleep`，单位分钟，0 = 永不）
3. **接通电源时关闭显示器**（`pmset -c displaysleep`，单位分钟，0 = 永不）

**系统即唯一数据源**：App 打开时读系统当前值，保存时把改动写回系统。三个值**不进** `clamshell-config.json`。

## 非目标（本次不做）

- 系统整体睡眠时间（`pmset sleep`）、磁盘睡眠等其他 pmset 参数
- 随睡眠/唤醒模式自动切换两套值
- `clamshell.lua` / `install.sh` / sudoers 的任何改动（sudoers 已放行整个 `/usr/bin/pmset`，无需变更）

## UI（`SettingsView.swift`）

Settings 页**顶部**新增分区「系统亮屏时间」，三行 Picker（离散档位，不用滑块）：

| 行 | 档位（分钟） |
|---|---|
| 启动屏幕保护程序 | 1 / 2 / 5 / 10 / 20 / 30 / 60 / 永不 |
| 电池供电时关闭显示器 | 1 / 2 / 5 / 10 / 15 / 20 / 30 / 45 / 60 / 90 / 120 / 180 / 永不 |
| 接通电源时关闭显示器 | 同上一行 |

- 系统当前值不在预设档位时（如手动 `pmset` 成 7 分钟），把该值动态插入档位列表（按数值排序位置），显示为「7 分钟」，不丢失真实值。
- 分区底部 caption：*「直接修改 macOS 系统设置（= 系统设置 → 锁定屏幕），保存时生效」*。
- 无 Battery Power 段（台式 Mac）时隐藏「电池供电」行。

## 数据模型与读写（新文件 `app/Sources/ClamshellModeApp/ScreenTimers.swift`）

```swift
struct ScreenTimers: Equatable {
    var screensaverMin: Int      // 0 = 永不
    var displaySleepBatteryMin: Int?  // nil = 系统无 Battery 段（隐藏该行）
    var displaySleepACMin: Int
}
```

- **读**（App 启动时执行一次，存进 view 的 state；同时留一份 loaded 快照做 diff）：
  - `pmset -g custom` → 解析 `Battery Power:` / `AC Power:` 两段各自的 `displaysleep`。
  - `defaults -currentHost read com.apple.screensaver idleTime` → 秒；读不到（域/键不存在）= 系统默认 **20 分钟**。秒数不是 60 的整倍数时四舍五入到最近分钟（最小 1 分钟）显示；因保存时只写改动项，不会无谓覆盖原始秒值。
- **写**（挂在现有「保存并重载」按钮流程里，与 config 保存并列）：逐项 diff loaded 快照，**只写改动过的**：
  - `sudo -n /usr/bin/pmset -b displaysleep <N>`
  - `sudo -n /usr/bin/pmset -c displaysleep <N>`
  - `defaults -currentHost write com.apple.screensaver idleTime -int <N*60>`（永不 = 0）
  - 写完回读一次刷新 state 与快照（回显确认）。
- 复用 `SystemInfo.runShell` 执行命令。

## 错误处理

- 载入时若 `SystemInfo.isSudoersConfigured == false`：分区顶部红字「pmset 免密 sudo 未配置，请到 Setup 页检查」，两个 displaysleep Picker 置灰（屏保行不依赖 sudo，仍可用）。
- 保存时任一写入命令失败：沿用现有 `saveStatus = .error(...)` 徽标显示失败原因，不中断其余保存步骤。
- `pmset` 在 displaysleep 与 sleep 时序矛盾时会向 stderr 打 Warning 但仍生效——忽略 stderr，以回读值为准。

## 验证计划

- `bash app/build-app.sh` 编译通过，App 正常打开。
- 每个 Picker 改一档保存后，用 `pmset -g custom` / `defaults -currentHost read com.apple.screensaver idleTime` 核对系统值。
- 打开系统设置 → 锁定屏幕，确认三个值同步显示（重点：**macOS 27 beta 上 `idleTime` 写入的生效性**——若系统设置 UI 不同步或屏保不按新时间启动，回报并调整写入方式）。
- 把「接通电源关闭显示器」从永不改成 1 分钟，实测 1 分钟后屏幕真的熄灭，再改回。
- 不改任何值直接保存 → 确认三条写入命令一条都没执行（diff 逻辑生效）。
