# 「系统亮屏时间」设置区 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Clamshell Mode.app 的 Settings 页新增「系统亮屏时间」分区，可查看/修改 macOS 锁定屏幕的 3 个闲置计时器（屏保启动、电池关显示器、电源关显示器），系统即唯一数据源。

**Architecture:** 新增 `ScreenTimers.swift`：纯解析/换算函数 + 可注入 runner 的系统读写层（读 `pmset -g custom` 与 `defaults -currentHost`，保存时只写 diff 出的改动项）。`SettingsView.swift` 顶部加一个分区（3 个离散档位 Picker），挂在现有「保存并重载」按钮流程里。三个值**不进** `clamshell-config.json`，`clamshell.lua` / `install.sh` 零改动。

**Tech Stack:** Swift 5.9 SPM（executable target + 新增 XCTest test target）、SwiftUI（macOS 14+）、`pmset`（sudoers 已放行整个 `/usr/bin/pmset`，`sudo -n` 免密）、`defaults`。

**Spec:** `docs/superpowers/specs/2026-07-30-system-screen-timers-design.md`

## Global Constraints

- **本目录不是 git 仓库** —— 所有「Commit」步骤省略，改动直接落盘。
- 所有命令都在**用户本机 Mac** 上运行；SPM 命令的工作目录是 `/Users/kris/Documents/clamshell/app`。
- 单位约定：UI 与内部模型一律用**分钟**，`0 = 永不`；仅 `com.apple.screensaver idleTime` 落盘时是**秒**（写入 = 分钟 × 60）。
- 屏保默认值：`idleTime` 键不存在时视为 **20 分钟**（系统默认）。
- UI 文案为中文，风格与现有 SettingsView 一致（分区标题 + caption 用 `.font(.caption).foregroundColor(.secondary)`）。
- 平台下限 macOS 14（`Package.swift` 现有 `platforms: [.macOS(.v14)]` 不动）。
- 用户机器为 macOS 27 beta：`idleTime` 写入生效性是唯一版本风险点，Task 3 有专门验证步骤。

---

### Task 1: ScreenTimers 模型 + 逻辑 + 单元测试

**Files:**
- Modify: `app/Package.swift`（加 test target）
- Create: `app/Sources/ClamshellModeApp/ScreenTimers.swift`
- Test: `app/Tests/ClamshellModeAppTests/ScreenTimersTests.swift`

**Interfaces:**
- Consumes: `SystemInfo.runShell(_:) -> String`（已存在，`SystemInfo.swift:5`；只回传 stdout，stderr 被丢弃、拿不到退出码 —— 所以写命令用 `&& echo __OK__` 判成败）
- Produces（Task 2 依赖，签名精确如下）:
  - `struct ScreenTimers: Equatable { var screensaverMin: Int; var displaySleepBatteryMin: Int?; var displaySleepACMin: Int }`
  - `ScreenTimersIO.screensaverBase: [Int]`、`ScreenTimersIO.displaySleepBase: [Int]`
  - `ScreenTimersIO.pickerOptions(base: [Int], current: Int) -> [Int]`
  - `ScreenTimersIO.readAll(runner: (String) -> String = SystemInfo.runShell) -> ScreenTimers`
  - `ScreenTimersIO.apply(_ new: ScreenTimers, previous: ScreenTimers, runner: (String) -> String = SystemInfo.runShell) -> String?`（nil = 全部成功）

- [ ] **Step 1: 在 `app/Package.swift` 加 test target**

整文件改为：

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClamshellModeApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClamshellModeApp",
            path: "Sources/ClamshellModeApp"
        ),
        .testTarget(
            name: "ClamshellModeAppTests",
            dependencies: ["ClamshellModeApp"],
            path: "Tests/ClamshellModeAppTests"
        )
    ]
)
```

- [ ] **Step 2: 写失败测试 `app/Tests/ClamshellModeAppTests/ScreenTimersTests.swift`**

```swift
import XCTest
@testable import ClamshellModeApp

final class ScreenTimersTests: XCTestCase {

    // 取自用户真机 `pmset -g custom` 的精简 fixture（键前有空格缩进、段名顶格带冒号）
    let fixture = """
    Battery Power:
     Sleep On Power Button 1
     powermode            0
     displaysleep         10
     sleep                1
     disksleep            10
    AC Power:
     Sleep On Power Button 1
     displaysleep         0
     sleep                0
    """

    // MARK: parseDisplaySleep

    func testParseDisplaySleepBattery() {
        XCTAssertEqual(ScreenTimersIO.parseDisplaySleep(pmsetOutput: fixture, section: "Battery Power"), 10)
    }

    func testParseDisplaySleepAC() {
        XCTAssertEqual(ScreenTimersIO.parseDisplaySleep(pmsetOutput: fixture, section: "AC Power"), 0)
    }

    func testParseDisplaySleepMissingSection() {
        XCTAssertNil(ScreenTimersIO.parseDisplaySleep(pmsetOutput: "AC Power:\n displaysleep 5", section: "Battery Power"))
    }

    // MARK: minutes(fromIdleSeconds:)

    func testMinutesFromIdleSeconds() {
        XCTAssertEqual(ScreenTimersIO.minutes(fromIdleSeconds: 0), 0)      // 永不
        XCTAssertEqual(ScreenTimersIO.minutes(fromIdleSeconds: 60), 1)
        XCTAssertEqual(ScreenTimersIO.minutes(fromIdleSeconds: 1200), 20)
        XCTAssertEqual(ScreenTimersIO.minutes(fromIdleSeconds: 90), 2)     // 四舍五入
        XCTAssertEqual(ScreenTimersIO.minutes(fromIdleSeconds: 10), 1)     // 最小 1 分钟
    }

    // MARK: pickerOptions

    func testPickerOptionsInsertsOddValueSorted() {
        XCTAssertEqual(ScreenTimersIO.pickerOptions(base: [1, 2, 5, 10], current: 7), [1, 2, 5, 7, 10, 0])
    }

    func testPickerOptionsKnownValueNoDuplicate() {
        XCTAssertEqual(ScreenTimersIO.pickerOptions(base: [1, 2, 5], current: 5), [1, 2, 5, 0])
    }

    func testPickerOptionsNeverAlwaysLast() {
        XCTAssertEqual(ScreenTimersIO.pickerOptions(base: [1, 2], current: 0), [1, 2, 0])
    }

    // MARK: readAll（注入 fake runner）

    func testReadAllParsesSystemOutput() {
        let timers = ScreenTimersIO.readAll { cmd in
            if cmd.contains("pmset") { return self.fixture }
            if cmd.contains("idleTime") { return "1200" }
            return ""
        }
        XCTAssertEqual(timers, ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: 10, displaySleepACMin: 0))
    }

    func testReadAllDefaultsTo20WhenIdleTimeMissing() {
        // defaults 读不到键时 stderr 报错、stdout 为空 → runShell 回传 ""
        let timers = ScreenTimersIO.readAll { cmd in cmd.contains("pmset") ? self.fixture : "" }
        XCTAssertEqual(timers.screensaverMin, 20)
    }

    func testReadAllNoBatterySection() {
        let timers = ScreenTimersIO.readAll { cmd in
            cmd.contains("pmset") ? "AC Power:\n displaysleep 0" : ""
        }
        XCTAssertNil(timers.displaySleepBatteryMin)
    }

    // MARK: apply（注入 fake runner，捕获命令）

    func testApplyOnlyWritesChangedValues() {
        var cmds: [String] = []
        let prev = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: 10, displaySleepACMin: 0)
        var new = prev
        new.displaySleepACMin = 15
        let err = ScreenTimersIO.apply(new, previous: prev) { cmd in cmds.append(cmd); return "__OK__" }
        XCTAssertNil(err)
        XCTAssertEqual(cmds.count, 1)
        XCTAssertTrue(cmds[0].contains("/usr/bin/pmset -c displaysleep 15"))
        XCTAssertTrue(cmds[0].contains("sudo -n"))
    }

    func testApplyNoChangesRunsNothing() {
        var cmds: [String] = []
        let t = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: 10, displaySleepACMin: 0)
        XCTAssertNil(ScreenTimersIO.apply(t, previous: t) { cmd in cmds.append(cmd); return "__OK__" })
        XCTAssertTrue(cmds.isEmpty)
    }

    func testApplyWritesIdleTimeInSeconds() {
        var cmds: [String] = []
        let prev = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: nil, displaySleepACMin: 0)
        var new = prev
        new.screensaverMin = 5
        _ = ScreenTimersIO.apply(new, previous: prev) { cmd in cmds.append(cmd); return "__OK__" }
        XCTAssertEqual(cmds.count, 1)
        XCTAssertTrue(cmds[0].contains("defaults -currentHost write com.apple.screensaver idleTime -int 300"))
        XCTAssertFalse(cmds[0].contains("sudo"))   // 屏保不需要 sudo
    }

    func testApplyReportsFailure() {
        let prev = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: 10, displaySleepACMin: 0)
        var new = prev
        new.screensaverMin = 5
        let err = ScreenTimersIO.apply(new, previous: prev) { _ in "" }   // 无 __OK__ = 命令失败
        XCTAssertNotNil(err)
        XCTAssertTrue(err!.contains("屏幕保护"))
    }

    func testApplySkipsBatteryWhenNil() {
        var cmds: [String] = []
        let prev = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: nil, displaySleepACMin: 0)
        var new = prev
        new.displaySleepACMin = 5
        _ = ScreenTimersIO.apply(new, previous: prev) { cmd in cmds.append(cmd); return "__OK__" }
        XCTAssertEqual(cmds.count, 1)
        XCTAssertTrue(cmds[0].contains("-c displaysleep 5"))
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
cd /Users/kris/Documents/clamshell/app && swift test 2>&1 | tail -20
```

Expected: 编译错误 `cannot find 'ScreenTimersIO' in scope`（类型还不存在）。
若报 executable target 不可测（如 `'main' attribute cannot be used ...` / top-level code 错误）：把 `ScreenTimers.swift` 挪进新建 library target `ClamshellCore`（`Sources/ClamshellCore/`，executable 加 `dependencies: ["ClamshellCore"]`，test target 依赖并 `@testable import ClamshellCore`，`ScreenTimers.swift` 里 `SystemInfo.runShell` 默认参数改为在调用侧显式传入），其余步骤不变。

- [ ] **Step 4: 实现 `app/Sources/ClamshellModeApp/ScreenTimers.swift`**

```swift
import Foundation

/// macOS 锁定屏幕的三个闲置计时器（单位分钟；0 = 永不）。
/// 系统本身是唯一数据源 —— 不进 clamshell-config.json。
struct ScreenTimers: Equatable {
    var screensaverMin: Int            // 启动屏幕保护程序
    var displaySleepBatteryMin: Int?   // 电池供电关闭显示器；nil = 系统无 Battery Power 段（台式机），UI 隐藏该行
    var displaySleepACMin: Int         // 接通电源关闭显示器
}

enum ScreenTimersIO {
    static let screensaverDefaultMin = 20
    static let screensaverBase = [1, 2, 5, 10, 20, 30, 60]
    static let displaySleepBase = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]

    // MARK: - 纯函数

    /// 从 `pmset -g custom` 输出解析指定电源段的 displaysleep 分钟数。
    /// 段名顶格以冒号结尾（"Battery Power:"），键行有缩进；找不到返回 nil。
    static func parseDisplaySleep(pmsetOutput: String, section: String) -> Int? {
        var inSection = false
        for rawLine in pmsetOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                inSection = (line == section + ":")
                continue
            }
            guard inSection else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == "displaysleep", let v = Int(parts[1]) {
                return v
            }
        }
        return nil
    }

    /// idleTime 秒 → 菜单分钟。0/负 = 永不；非整分钟四舍五入，最小 1 分钟。
    static func minutes(fromIdleSeconds sec: Int) -> Int {
        if sec <= 0 { return 0 }
        return max(1, Int((Double(sec) / 60.0).rounded()))
    }

    /// Picker 档位：base 升序 + current（>0 且不在 base 时按序插入，不丢真实系统值）+ 末尾 0（永不）。
    static func pickerOptions(base: [Int], current: Int) -> [Int] {
        var opts = base
        if current > 0 && !opts.contains(current) {
            opts.append(current)
            opts.sort()
        }
        opts.append(0)
        return opts
    }

    // MARK: - 系统读写（runner 可注入以便单测）

    static func readAll(runner: (String) -> String = SystemInfo.runShell) -> ScreenTimers {
        let pmout = runner("/usr/bin/pmset -g custom")
        let battery = parseDisplaySleep(pmsetOutput: pmout, section: "Battery Power")
        let ac = parseDisplaySleep(pmsetOutput: pmout, section: "AC Power") ?? 0
        let idleRaw = runner("/usr/bin/defaults -currentHost read com.apple.screensaver idleTime")
        let saver = Int(idleRaw).map { minutes(fromIdleSeconds: $0) } ?? screensaverDefaultMin
        return ScreenTimers(screensaverMin: saver, displaySleepBatteryMin: battery, displaySleepACMin: ac)
    }

    /// 逐项 diff，只写改动过的值。返回 nil = 全部成功，否则返回汇总错误。
    /// runShell 只回传 stdout（拿不到退出码），故以 `&& echo __OK__` 判定成功。
    static func apply(_ new: ScreenTimers, previous: ScreenTimers,
                      runner: (String) -> String = SystemInfo.runShell) -> String? {
        var errors: [String] = []
        func run(_ cmd: String, _ what: String) {
            if !runner(cmd + " && echo __OK__").contains("__OK__") {
                errors.append("\(what)写入失败")
            }
        }
        if let b = new.displaySleepBatteryMin, b != previous.displaySleepBatteryMin {
            run("/usr/bin/sudo -n /usr/bin/pmset -b displaysleep \(b)", "电池关闭显示器")
        }
        if new.displaySleepACMin != previous.displaySleepACMin {
            run("/usr/bin/sudo -n /usr/bin/pmset -c displaysleep \(new.displaySleepACMin)", "电源关闭显示器")
        }
        if new.screensaverMin != previous.screensaverMin {
            run("/usr/bin/defaults -currentHost write com.apple.screensaver idleTime -int \(new.screensaverMin * 60)", "屏幕保护程序时间")
        }
        return errors.isEmpty ? nil : errors.joined(separator: "；")
    }
}
```

- [ ] **Step 5: 跑测试确认全绿**

```bash
cd /Users/kris/Documents/clamshell/app && swift test 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`，15 个测试 0 失败。

---

### Task 2: SettingsView 新分区 + 保存接线

**Files:**
- Modify: `app/Sources/ClamshellModeApp/SettingsView.swift`（新分区插在 Form 最顶部、`Section("亮度过渡")` 之前；save() 接入 apply）

**Interfaces:**
- Consumes（Task 1 产物）: `ScreenTimers`、`ScreenTimersIO.readAll()`、`ScreenTimersIO.apply(_:previous:)`、`ScreenTimersIO.pickerOptions(base:current:)`、`ScreenTimersIO.screensaverBase`、`ScreenTimersIO.displaySleepBase`；以及已有 `SystemInfo.isSudoersConfigured`（`SystemInfo.swift:63`）
- Produces: 无（终端消费者）

- [ ] **Step 1: 加 state 与加载逻辑**

在 `SettingsView` 的 `@State private var saveStatus` 下面加：

```swift
    @State private var screenTimers = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: nil, displaySleepACMin: 0)
    @State private var loadedTimers: ScreenTimers? = nil   // 读入快照，diff 基准；nil = 尚未加载
    @State private var sudoOK = true
```

在 `.formStyle(.grouped)` 与 `.padding()` 之间**不加**东西；在 `.padding()` 之后、`.toolbar` 之前加：

```swift
        .onAppear {
            guard loadedTimers == nil else { return }
            DispatchQueue.global().async {
                let timers = ScreenTimersIO.readAll()
                let sudo = SystemInfo.isSudoersConfigured
                DispatchQueue.main.async {
                    screenTimers = timers
                    loadedTimers = timers
                    sudoOK = sudo
                }
            }
        }
```

- [ ] **Step 2: 加 UI 分区（Form 内第一个 Section，放在 `Section("亮度过渡")` 之前）**

```swift
            Section("系统亮屏时间") {
                if !sudoOK {
                    Label("pmset 免密 sudo 未配置，请到 Setup 页检查", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
                timerPicker("启动屏幕保护程序",
                            selection: $screenTimers.screensaverMin,
                            base: ScreenTimersIO.screensaverBase,
                            loaded: loadedTimers?.screensaverMin)
                if screenTimers.displaySleepBatteryMin != nil {
                    timerPicker("电池供电时关闭显示器",
                                selection: Binding(
                                    get: { screenTimers.displaySleepBatteryMin ?? 0 },
                                    set: { screenTimers.displaySleepBatteryMin = $0 }
                                ),
                                base: ScreenTimersIO.displaySleepBase,
                                loaded: loadedTimers.flatMap { $0.displaySleepBatteryMin })
                        .disabled(!sudoOK)
                }
                timerPicker("接通电源时关闭显示器",
                            selection: $screenTimers.displaySleepACMin,
                            base: ScreenTimersIO.displaySleepBase,
                            loaded: loadedTimers?.displaySleepACMin)
                    .disabled(!sudoOK)
                Text("直接修改 macOS 系统设置（= 系统设置 → 锁定屏幕），保存时生效")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(loadedTimers == nil)   // 系统值读到之前整区不可交互
```

在 `SettingsView` 里（`statusBadge` 之前）加私有 helper —— 档位列表基于 **loaded** 值计算而不是当前选择，这样把 7 分钟这类非常规值改走后菜单里它仍在，可以改回去：

```swift
    private func timerPicker(_ label: String, selection: Binding<Int>, base: [Int], loaded: Int?) -> some View {
        Picker(label, selection: selection) {
            ForEach(ScreenTimersIO.pickerOptions(base: base, current: loaded ?? 0), id: \.self) { m in
                Text(m == 0 ? "永不" : "\(m) 分钟").tag(m)
            }
        }
    }
```

- [ ] **Step 3: save() 接入 apply（整函数替换）**

```swift
    private func save() {
        saveStatus = .saving
        let timersToApply = loadedTimers.map { (screenTimers, $0) }   // 主线程取快照再进后台
        DispatchQueue.global().async {
            do {
                try config.save()
                IconRenderer.regenerate(sleep: config.iconSleep, awake: config.iconAwake)
                SystemInfo.reloadHammerspoon()
                var timerError: String? = nil
                var fresh: ScreenTimers? = nil
                if let (new, prev) = timersToApply {
                    timerError = ScreenTimersIO.apply(new, previous: prev)
                    fresh = ScreenTimersIO.readAll()   // 回读确认，UI 回显系统真实值
                }
                DispatchQueue.main.async {
                    if let fresh {
                        screenTimers = fresh
                        loadedTimers = fresh
                    }
                    if let timerError {
                        saveStatus = .error(timerError)
                    } else {
                        saveStatus = .saved
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if case .saved = saveStatus { saveStatus = .idle }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { saveStatus = .error(error.localizedDescription) }
            }
        }
    }
```

- [ ] **Step 4: 编译 + 测试确认不回归**

```bash
cd /Users/kris/Documents/clamshell/app && swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3
```

Expected: `Build complete!`；测试仍全绿。

---

### Task 3: 安装、端到端验证、文档

**Files:**
- Modify: `README.zh.md:69`、`README.md:71`（Settings 功能清单补一项）

**Interfaces:**
- Consumes: Task 2 完成后的完整 App
- Produces: 无

- [ ] **Step 1: 记录系统当前值（验证基线，也用于最后还原核对）**

```bash
pmset -g custom | grep -E "Power|displaysleep"; defaults -currentHost read com.apple.screensaver idleTime 2>&1
```

Expected（按 2026-07-30 现状）: Battery `displaysleep 10`、AC `displaysleep 0`、idleTime 键不存在（= 默认 20 分钟）。

- [ ] **Step 2: 编译安装并打开 App**

```bash
cd /Users/kris/Documents/clamshell/app && bash build-app.sh && open "/Applications/Clamshell Mode.app"
```

Expected: `✅ 装好了`；App 打开后 Settings 页顶部出现「系统亮屏时间」分区，三行分别显示 **20 分钟 / 10 分钟 / 永不**，无红字警告。

- [ ] **Step 3: 验证 AC displaysleep 写入与还原**

GUI 里把「接通电源时关闭显示器」改为 **1 分钟** → 保存并重载 → 出现「已保存」。

```bash
pmset -g custom | grep -A20 "AC Power" | grep displaysleep
```

Expected: `displaysleep 1`。（可选真机行为验证，需接着电源：晾着 Mac 不动 1 分钟，确认屏幕真的熄灭——动一下触控板又亮回。）再在 GUI 改回**永不** → 保存 → 同一命令输出 `displaysleep 0`。

- [ ] **Step 4: 验证电池 displaysleep 写入与还原**

GUI 里把「电池供电时关闭显示器」10 → **15 分钟** → 保存。

```bash
pmset -g custom | grep -B1 -A20 "Battery Power" | grep displaysleep | head -1
```

Expected: `displaysleep 15`。改回 **10 分钟** → 保存 → 输出 `displaysleep 10`。

- [ ] **Step 5: 验证屏保 idleTime 写入（macOS 27 beta 重点风险项）**

GUI 里把「启动屏幕保护程序」改为 **5 分钟** → 保存。

```bash
defaults -currentHost read com.apple.screensaver idleTime
```

Expected: `300`。然后打开系统设置 → 锁定屏幕，确认「闲置后启动屏幕保护程序」显示 **5 分钟**（若系统设置不同步/不生效，停下来回报用户，讨论改用别的写入通道——不要自行硬试私有 API）。最后 GUI 改回 **20 分钟** → 保存 → `defaults` 读出 `1200`（显式 1200 与"未设置的默认 20 分钟"效果等同）。

- [ ] **Step 6: 验证无改动保存不写系统**

不动三个 Picker，直接点保存。Expected: 「已保存」正常出现，`pmset -g custom` 与 idleTime 值与 Step 5 结束时完全一致（diff 逻辑已有单测 `testApplyNoChangesRunsNothing` 兜底，这里只做行为 sanity check）。

- [ ] **Step 7: README 两处文档更新**

`README.zh.md:69` 改为：

```markdown
- **Settings**：系统亮屏时间（屏保启动 / 电池关屏 / 电源关屏，直接读写系统设置）、手机号、提醒延时（1–120 分钟）、亮度过渡时长、快捷键、菜单栏图标（任意 SF Symbol）、各功能独立开关。**保存后自动重载**
```

`README.md:71` 改为：

```markdown
- **Settings**: system display timers (screen saver start / display-off on battery / display-off on power, reads & writes macOS settings directly), phone number, reminder delay (1–120 min), brightness fade duration, hotkey, menu bar icon (any SF Symbol), and per-feature toggles. **Auto-reloads Hammerspoon on save**
```

- [ ] **Step 8: 收尾核对**

```bash
pmset -g custom | grep -E "Power|displaysleep"; defaults -currentHost read com.apple.screensaver idleTime
```

Expected: Battery `displaysleep 10`、AC `displaysleep 0`、idleTime `1200`（唯一与基线的差异：屏保从"未设置(默认20)"变成显式 1200 秒 = 同样的 20 分钟，行为无变化）。向用户建议跑 `/sync` 记录本次改动（目录非 git 仓库，无 commit）。
