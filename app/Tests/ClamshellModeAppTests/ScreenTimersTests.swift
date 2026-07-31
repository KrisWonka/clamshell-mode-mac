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
