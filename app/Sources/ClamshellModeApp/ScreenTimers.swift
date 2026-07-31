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
