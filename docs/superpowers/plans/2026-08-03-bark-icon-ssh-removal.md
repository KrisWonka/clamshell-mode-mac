# Bark 提醒迁移 + SSH 移除 + App 图标 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除整套 iPhone-SSH 远程切换功能，把长时间合盖提醒从 iMessage 换成 Bark（barkKey + 官方服务器），收编孤本光标/WindowServer 修复进 main，给 App 做贝壳母题图标，最后部署同步 + 推 GitHub。

**Architecture:** 在现有架构内等量替换：Config JSON 加 `barkKey` 删 `phone`（decodeIfPresent 容错改造），lua 换 `sendBark`（hs.http.asyncGet）并收编 `lastSleepDisabled` 缓存 + 15 秒菜单栏刷新，GUI 改 Settings 分区/砍 Setup 卡片，图标走 SVG → Chrome 无头渲染 → iconutil 管线。

**Tech Stack:** Swift 5.9 SPM + XCTest、SwiftUI (macOS 14+)、Hammerspoon Lua（hs.http/hs.timer/hs.menubar）、Bark（`https://api.day.app/<key>/<title>/<body>`）、headless Chrome + sips + iconutil。

**Spec:** `docs/superpowers/specs/2026-07-31-bark-notify-icon-design.md`（含 2026-08-03 增补）

## Global Constraints

- 所有命令在**用户本机 Mac**跑；SPM 命令工作目录 `/Users/kris/Documents/clamshell/app`。
- 本目录**是 git 仓库**（main，origin=GitHub），每个任务结尾 commit；commit message 末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。**未经用户要求不 push**（push 是 Task 5 的显式步骤）。
- Bark URL 形态固定：`https://api.day.app/<barkKey>/<title>/<body>`，title 固定 `Clamshell Mode`，逐段 URL 编码；`barkKey` 为空 = 不推送。**不支持自建服务器**（YAGNI）。
- 配置迁移安全：老 JSON（含 `phone`、缺 `barkKey`/`alertSleep`/`alertAwake`）解码**不得整体失败**。
- 光标修复收编须保留部署版注释（WindowServer `_CGXPackagesSetWindowConstraints: Invalid window` 的解释）。
- 菜单栏刷新间隔 `cfg.menuRefreshInterval or 15`，lua-only 可选键，**不进 GUI**。
- 朋友机器（tsc@100.100.15.127）这轮**不动**。
- 现场备份已存在：`~/.hammerspoon/backup-20260803-052548/`，不要删。
- clamshell.lua / install.sh / README 以 git main @ 11fa55d 之后的版本为基线（执行任何编辑前先 Read 当前文件）。

---

### Task 1: ClamshellConfig — barkKey + 解码容错（TDD）

**Files:**
- Modify: `app/Sources/ClamshellModeApp/Config.swift`
- Test (Create): `app/Tests/ClamshellModeAppTests/ConfigTests.swift`

**Interfaces:**
- Consumes: 无（纯模型层）
- Produces（Task 3 依赖）: `ClamshellConfig.barkKey: String`（默认 `""`；`phone` 字段从此不存在）；`ClamshellConfig()`（全默认 memberwise init，保持可用）；`load()/save()` 签名不变。

- [ ] **Step 1: 写失败测试 `app/Tests/ClamshellModeAppTests/ConfigTests.swift`**

```swift
import XCTest
@testable import ClamshellModeApp

final class ConfigTests: XCTestCase {

    /// 老版本 config（含 phone、缺 barkKey/alertSleep/alertAwake）必须解码成功且旧值保留
    func testDecodeOldFormatJSONWithoutBarkKey() throws {
        let old = """
        {
          "fadeDuration": 2.5, "fadeEnabled": false,
          "hotkeyEnabled": true, "hotkeyKey": "7", "hotkeyMods": ["cmd"],
          "iconAwake": "bolt.fill", "iconSleep": "moon",
          "notifyDelaySec": 600, "notifyEnabled": true,
          "phone": "+15551234567", "pollInterval": 2
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(ClamshellConfig.self, from: old)
        XCTAssertEqual(cfg.barkKey, "")               // 缺失的新字段 → 默认
        XCTAssertEqual(cfg.fadeDuration, 2.5)         // 旧值保留
        XCTAssertEqual(cfg.hotkeyKey, "7")
        XCTAssertEqual(cfg.notifyDelaySec, 600)
        XCTAssertTrue(cfg.notifyEnabled)
        XCTAssertEqual(cfg.alertSleep, "Clam Sleep")  // 缺失字段 → 默认（现状会整体解码失败，此为顺带修复）
    }

    func testDecodeEmptyJSONGivesDefaults() throws {
        let cfg = try JSONDecoder().decode(ClamshellConfig.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(cfg, ClamshellConfig())
    }

    func testEncodeContainsBarkKeyAndNoPhone() throws {
        var cfg = ClamshellConfig()
        cfg.barkKey = "testkey123"
        let json = String(data: try JSONEncoder().encode(cfg), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"barkKey\""))
        XCTAssertFalse(json.contains("\"phone\""))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/kris/Documents/clamshell/app && swift test 2>&1 | tail -5
```

Expected: 编译错误 `value of type 'ClamshellConfig' has no member 'barkKey'`。

- [ ] **Step 3: 改 `Config.swift`**

`phone` 字段删除、`barkKey` 加在首位，struct 主体其余不动；文件末尾追加 extension（**init(from:) 必须放 extension，否则合成 memberwise init 丢失、`ClamshellConfig()` 编译不过**）：

```swift
import Foundation

struct ClamshellConfig: Codable, Equatable {
    var barkKey: String = ""
    var notifyDelaySec: Int = 15 * 60
    var notifyEnabled: Bool = false
    var fadeDuration: Double = 1.5
    var fadeEnabled: Bool = true
    var pollInterval: Double = 1.0
    var hotkeyMods: [String] = ["ctrl", "alt", "cmd"]
    var hotkeyKey: String = "6"
    var hotkeyEnabled: Bool = true
    var iconSleep: String = "zzz"
    var iconAwake: String = "cup.and.saucer.fill"
    var alertSleep: String = "Clam Sleep"
    var alertAwake: String = "Clam Awake"

    static let configPath: String = {
        NSString(string: "~/.hammerspoon/clamshell-config.json").expandingTildeInPath
    }()

    static func load() -> ClamshellConfig {
        let url = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(ClamshellConfig.self, from: data)
        else {
            return ClamshellConfig()
        }
        return cfg
    }

    func save() throws {
        let url = URL(fileURLWithPath: Self.configPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

// 全字段 decodeIfPresent + 默认兜底：老 JSON 缺新字段（barkKey/alertSleep/…）或含
// 已废弃字段（phone）时都不能整体解码失败，否则 GUI 所有设置静默回退默认。
extension ClamshellConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClamshellConfig()
        barkKey        = try c.decodeIfPresent(String.self,   forKey: .barkKey)        ?? d.barkKey
        notifyDelaySec = try c.decodeIfPresent(Int.self,      forKey: .notifyDelaySec) ?? d.notifyDelaySec
        notifyEnabled  = try c.decodeIfPresent(Bool.self,     forKey: .notifyEnabled)  ?? d.notifyEnabled
        fadeDuration   = try c.decodeIfPresent(Double.self,   forKey: .fadeDuration)   ?? d.fadeDuration
        fadeEnabled    = try c.decodeIfPresent(Bool.self,     forKey: .fadeEnabled)    ?? d.fadeEnabled
        pollInterval   = try c.decodeIfPresent(Double.self,   forKey: .pollInterval)   ?? d.pollInterval
        hotkeyMods     = try c.decodeIfPresent([String].self, forKey: .hotkeyMods)     ?? d.hotkeyMods
        hotkeyKey      = try c.decodeIfPresent(String.self,   forKey: .hotkeyKey)      ?? d.hotkeyKey
        hotkeyEnabled  = try c.decodeIfPresent(Bool.self,     forKey: .hotkeyEnabled)  ?? d.hotkeyEnabled
        iconSleep      = try c.decodeIfPresent(String.self,   forKey: .iconSleep)      ?? d.iconSleep
        iconAwake      = try c.decodeIfPresent(String.self,   forKey: .iconAwake)      ?? d.iconAwake
        alertSleep     = try c.decodeIfPresent(String.self,   forKey: .alertSleep)     ?? d.alertSleep
        alertAwake     = try c.decodeIfPresent(String.self,   forKey: .alertAwake)     ?? d.alertAwake
    }
}
```

- [ ] **Step 4: 跑测试**

```bash
cd /Users/kris/Documents/clamshell/app && swift test 2>&1 | grep -E "Executed|error" | tail -3
```

Expected: 编译**先失败**——`SettingsView.swift` 仍引用 `config.phone`。这是预期的跨任务耦合：本步只需临时把 SettingsView 里 `TextField("+8613812345678", text: $config.phone)` 一行改成 `TextField("", text: $config.barkKey)`（Task 3 会整段重写该分区）。改完重跑，Expected: `Executed 18 tests, with 0 failures`（15 旧 + 3 新）。

- [ ] **Step 5: Commit**

```bash
cd /Users/kris/Documents/clamshell && git add app/ && git commit -m "feat(config): replace phone with barkKey; tolerant decoding for config migration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: clamshell.lua — sendBark + 光标/WindowServer 修复收编

**Files:**
- Modify: `clamshell.lua`（仓库根；基线 = 11fa55d 版本，动手前先 Read）

**Interfaces:**
- Consumes: `cfg.barkKey`（Task 1 定义的 JSON 键）；Hammerspoon API `hs.http.asyncGet` / `hs.http.encodeForQuery`
- Produces: 运行时行为（Task 5 部署验证依赖）；可选配置键 `menuRefreshInterval`（数字秒，缺省 15）

- [ ] **Step 1: 五处修改**

① cfg 默认表：`phone = "",` → `barkKey = "",`

② `refreshMenu` 整个函数替换为（含前置注释与 `lastSleepDisabled`）：

```lua
-- 只在状态真正变化时才重设菜单栏项。无条件每秒重设会让 macOS 反复重排整条
-- 菜单栏，在 macOS 27 上表现为 WindowServer 刷 _CGXPackagesSetWindowConstraints:
-- Invalid window（约 120 次/分钟），进而偶发 set_cursor_surface 失败、光标不变形。
local lastSleepDisabled = nil

local function refreshMenu(force)
  if not lidMenu then return end
  local disabled = getSleepDisabled()
  if not force and disabled == lastSleepDisabled then return end
  lastSleepDisabled = disabled
  if disabled then
    if iconAwake then lidMenu:setIcon(iconAwake, true); lidMenu:setTitle(nil)
    else lidMenu:setTitle("☕") end
    lidMenu:setTooltip("合盖不睡眠（程序继续跑）— 点击切回默认")
  else
    if iconSleep then lidMenu:setIcon(iconSleep, true); lidMenu:setTitle(nil)
    else lidMenu:setTitle("☾") end
    lidMenu:setTooltip("合盖会睡眠（默认）— 点击保持唤醒")
  end
end
```

③ `toggleClamshell` 内 `refreshMenu()` → `refreshMenu(true)`（`setClickCallback` 后面的初始 `refreshMenu()` 也改成 `refreshMenu(true)`）。

④ menuTimer 两行替换为：

```lua
-- 菜单栏指示器只反映 SleepDisabled 状态，而它只会被本模块的热键/点击改动（那两条
-- 路径已经主动调 refreshMenu(true)）。外部改动极罕见，所以这里不需要 1 秒轮询——
-- 每次轮询都要 fork 一个 `pmset -g | awk` 子进程，是剩余 Invalid window 的来源。
local menuInterval = cfg.menuRefreshInterval or 15
menuTimer = hs.timer.doEvery(menuInterval, refreshMenu)  -- 全局：防 GC
menuTimer:start()
```

⑤ `sendIMessage` 整个函数替换为 `sendBark`，lidPoller 里两处 `phone` 守卫与调用同步改：

```lua
local function sendBark(text)
  if not cfg.notifyEnabled or not cfg.barkKey or cfg.barkKey == "" then return end
  local url = "https://api.day.app/" .. cfg.barkKey
    .. "/" .. hs.http.encodeForQuery("Clamshell Mode")
    .. "/" .. hs.http.encodeForQuery(text)
  hs.http.asyncGet(url, nil, function(status, body, _)
    if status ~= 200 then
      print("[clamshell] Bark notify failed: " .. tostring(status) .. " " .. tostring(body))
    end
  end)
end
```

lidPoller 内：`if cfg.notifyEnabled and cfg.phone and cfg.phone ~= "" then` → `if cfg.notifyEnabled and cfg.barkKey and cfg.barkKey ~= "" then`；`sendIMessage(string.format(` → `sendBark(string.format(`。提醒文案不动。

- [ ] **Step 2: 语法自检**

```bash
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c "print(loadfile('/Users/kris/Documents/clamshell/clamshell.lua') and 'syntax OK' or 'syntax FAIL')" 2>/dev/null \
  || python3 -c "print('hs CLI 不可用，跳过静态检查（Task 5 部署时会真实加载验证）')"
```

Expected: `syntax OK`（或跳过提示——部署步骤兜底）。

- [ ] **Step 3: 核对与部署版的语义等价**

```bash
diff ~/Documents/clamshell/clamshell.lua ~/.hammerspoon/clamshell.lua
```

Expected 差异**只有**：(a) cfg 默认键名 `barkKey` vs `barkURL`；(b) sendBark 的 URL 拼接方式（key+标题段 vs 整 URL）；(c) lidPoller 守卫键名。其余（GC 注释、光标修复、menuInterval）应零差异——有额外差异必须逐条解释或修正。

- [ ] **Step 4: Commit**

```bash
cd /Users/kris/Documents/clamshell && git add clamshell.lua && git commit -m "feat(lua): Bark notifications via barkKey; adopt menubar cursor-storm fix from field

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: GUI — Bark 分区、Setup 瘦身、SystemInfo 清理、install.sh

**Files:**
- Modify: `app/Sources/ClamshellModeApp/SettingsView.swift`（iMessage 分区 → Bark 分区 + 测试推送）
- Modify: `app/Sources/ClamshellModeApp/SetupView.swift`（整文件替换）
- Modify: `app/Sources/ClamshellModeApp/SystemInfo.swift`（整文件替换）
- Modify: `app/Sources/ClamshellModeApp/ContentView.swift`（AboutView 图标行）
- Modify: `install.sh`（默认 JSON + 结尾文案）

**Interfaces:**
- Consumes: `config.barkKey`（Task 1）；`SystemInfo.runShell/isHammerspoonRunning/isSudoersConfigured/reloadHammerspoon`（保留项）
- Produces: 无（终端消费者）

- [ ] **Step 1: SettingsView — 撤销 Task 1 的临时改动，整段替换 iMessage 分区**

删除 `Section("iMessage 长时间合盖提醒") { ... }` 整块（含 Task 1 临时改的 TextField 行），原位换为：

```swift
            Section("Bark 长时间合盖提醒") {
                Toggle("启用", isOn: $config.notifyEnabled)
                HStack {
                    Text("Device Key")
                    TextField("在 Bark App 首页复制", text: $config.barkKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("发送测试推送") { sendTestPush() }
                        .disabled(config.barkKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    testPushBadge
                }
                .disabled(!config.notifyEnabled)
                HStack {
                    Text("延时阈值")
                    Slider(
                        value: Binding(
                            get: { Double(config.notifyDelaySec) / 60.0 },
                            set: { config.notifyDelaySec = Int($0 * 60) }
                        ),
                        in: 1...120, step: 1
                    )
                    Text("\(config.notifyDelaySec / 60) 分钟")
                        .frame(width: 80, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!config.notifyEnabled)
                Text("App Store 安装 Bark，打开 App 首页复制 device key。唤醒模式下合盖超过阈值，iPhone 收到推送提醒。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
```

`SettingsView` 里加 state（`sudoOK` 之后）、badge 与发送函数（`timerPicker` 之后）：

```swift
    @State private var testPushStatus: TestPushStatus = .idle

    enum TestPushStatus { case idle, sending, ok, fail(String) }

    @ViewBuilder
    private var testPushBadge: some View {
        switch testPushStatus {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView().controlSize(.small)
        case .ok:
            Label("已发送", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .fail(let msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    private func sendTestPush() {
        testPushStatus = .sending
        let key = config.barkKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = "Clamshell Mode".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "ClamshellMode"
        let body = "测试推送 ✓".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "test"
        guard let url = URL(string: "https://api.day.app/\(key)/\(title)/\(body)") else {
            testPushStatus = .fail("URL 无效"); return
        }
        URLSession.shared.dataTask(with: url) { _, resp, err in
            DispatchQueue.main.async {
                if let err {
                    testPushStatus = .fail(err.localizedDescription)
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    testPushStatus = .ok
                } else {
                    testPushStatus = .fail("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                }
            }
        }.resume()
    }
```

- [ ] **Step 2: SetupView.swift 整文件替换**

```swift
import SwiftUI

struct SetupView: View {
    @State private var hsRunning = SystemInfo.isHammerspoonRunning
    @State private var sudoersOk = SystemInfo.isSudoersConfigured
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem {
                Button(action: refresh) {
                    Image(systemName: refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .help("刷新状态")
            }
        }
    }

    private func refresh() {
        refreshing = true
        DispatchQueue.global().async {
            let h = SystemInfo.isHammerspoonRunning
            let su = SystemInfo.isSudoersConfigured
            DispatchQueue.main.async {
                hsRunning = h
                sudoersOk = su
                refreshing = false
            }
        }
    }

    private var statusCard: some View {
        GroupBox(label: Label("系统状态", systemImage: "checkmark.seal")) {
            VStack(alignment: .leading, spacing: 6) {
                statusRow("Hammerspoon 运行中", hsRunning, hint: hsRunning ? nil : "启动 Hammerspoon")
                statusRow("pmset 免密 sudo", sudoersOk, hint: sudoersOk ? nil : "运行 install.sh 配置")
            }
            .padding(8)
        }
    }

    private func statusRow(_ name: String, _ ok: Bool, hint: String?) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
            Text(name)
            Spacer()
            if let hint = hint { Text(hint).font(.caption).foregroundColor(.secondary) }
        }
    }
}
```

- [ ] **Step 3: SystemInfo.swift 整文件替换**（删 `isSshEnabled`/`localHostname`/`networkAddresses`/`friendlyLabel`/`openShortcutsApp`/`username`/`copyToClipboard`/`sleepDisabled`——grep 已确认无引用）

```swift
import Foundation
import AppKit

enum SystemInfo {
    static func runShell(_ command: String) -> String {
        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isHammerspoonRunning: Bool {
        !runShell("pgrep -lf Hammerspoon").isEmpty
    }

    static var isSudoersConfigured: Bool {
        runShell("/usr/bin/sudo -n /usr/bin/pmset -g 1>/dev/null 2>&1 && echo ok").contains("ok")
    }

    static func reloadHammerspoon() {
        _ = runShell("osascript -e 'quit app \"Hammerspoon\"' 2>/dev/null; sleep 1; pkill -x Hammerspoon 2>/dev/null; sleep 1; open -a Hammerspoon")
    }
}
```

（注意 `reloadHammerspoon` 顺带对齐 install.sh 的 quit+pkill+open 语义——原版对运行中的 HS 只 quit+open，同样有"没真正重载"的隐患。）

- [ ] **Step 4: ContentView.swift 的 AboutView 图标行**

`Image(systemName: "laptopcomputer")` → `Image(nsImage: NSApp.applicationIconImage)`（`.resizable().scaledToFit().frame(width: 80, height: 80)` 保留，删掉那行 `.foregroundColor(.accentColor)`）。

- [ ] **Step 5: install.sh 两处**

① 默认 JSON 里 `  "phone" : "",` → `  "barkKey" : "",`
② 结尾 heredoc `- Spotlight 搜「Clamshell」打开 GUI 配置（手机号 / 快捷键 / 图标 / 时长等）` → `- Spotlight 搜「Clamshell」打开 GUI 配置（Bark 提醒 / 快捷键 / 图标 / 时长等）`

- [ ] **Step 6: 编译 + 全测试**

```bash
cd /Users/kris/Documents/clamshell/app && swift build 2>&1 | tail -2 && swift test 2>&1 | grep Executed | tail -2
```

Expected: `Build complete!`；`Executed 18 tests, with 0 failures`。

- [ ] **Step 7: Commit**

```bash
cd /Users/kris/Documents/clamshell && git add app/ install.sh && git commit -m "feat(gui): Bark reminder section with test push; drop SSH remote-trigger UI

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: App 图标（贝壳母题）——变体生成与选稿由主会话执行

**Files:**
- Create: `app/AppIcon.svg`（定稿母版）+ `app/AppIcon.icns`
- Modify: `app/build-app.sh`（拷 icns + Info.plist 图标键）
- 临时产物放 scratchpad，不进仓库

**Interfaces:**
- Consumes: 无
- Produces: bundle 内 `Contents/Resources/AppIcon.icns` + Info.plist `CFBundleIconFile`（AboutView 的 `NSApp.applicationIconImage` 自动拾取）

**注意：Step 2 的选稿需要 AskUserQuestion + 开 Preview 给用户看，必须由主会话执行，不能交给 subagent。**

- [ ] **Step 1: 写变体 SVG 并渲染 1024px PNG**

三个变体共用同一几何（闭合贝壳 + 发光缝隙 + 扇脊），仅换配色。V1（深海夜蓝）完整 SVG——存 `/private/tmp/claude-501/-Users-kris-Documents-clamshell/84a7ad4f-d42b-4482-bc81-40441c204e0f/scratchpad/icon-v1.svg`：

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#232a63"/>
      <stop offset="1" stop-color="#0d1130"/>
    </linearGradient>
    <linearGradient id="shellTop" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#f0f3fb"/>
      <stop offset="1" stop-color="#a9b6dc"/>
    </linearGradient>
    <linearGradient id="shellBottom" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8894c0"/>
      <stop offset="1" stop-color="#5a6491"/>
    </linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
    <filter id="softGlow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="6"/>
    </filter>
  </defs>

  <!-- macOS squircle 背景 -->
  <rect x="64" y="64" width="896" height="896" rx="200" fill="url(#bg)"/>

  <!-- 缝隙泛光（在贝壳后面，向四周晕开） -->
  <ellipse cx="512" cy="580" rx="300" ry="46" fill="#7fd7ff" opacity="0.55" filter="url(#glow)"/>

  <!-- 上壳：扇形穹顶 -->
  <path d="M212,568 C212,362 342,238 512,238 C682,238 812,362 812,568
           L212,568 Z" fill="url(#shellTop)"/>
  <!-- 扇脊（从缝隙中心向穹顶放射） -->
  <g stroke="#7c88b4" stroke-width="10" stroke-linecap="round" opacity="0.55">
    <line x1="512" y1="560" x2="286" y2="430"/>
    <line x1="512" y1="560" x2="360" y2="322"/>
    <line x1="512" y1="560" x2="512" y2="262"/>
    <line x1="512" y1="560" x2="664" y2="322"/>
    <line x1="512" y1="560" x2="738" y2="430"/>
  </g>
  <!-- 穹顶高光 -->
  <ellipse cx="420" cy="330" rx="150" ry="70" fill="#ffffff" opacity="0.16" transform="rotate(-18 420 330)"/>

  <!-- 发光缝隙：亮核 -->
  <rect x="240" y="572" width="544" height="16" rx="8" fill="#bfeaff" filter="url(#softGlow)"/>
  <rect x="272" y="575" width="480" height="10" rx="5" fill="#ffffff"/>

  <!-- 下壳：浅碟 -->
  <path d="M232,600 C286,700 738,700 792,600 C700,668 324,668 232,600 Z"
        fill="url(#shellBottom)"/>
</svg>
```

V2（暖珊瑚）：`bg` stops `#3a1f4d → #170f2a`；`shellTop` `#ffe3d6 → #ff9a80`；`shellBottom` `#d8705c → #9c4436`；扇脊 stroke `#c96a52`；泛光/亮核把 `#7fd7ff`→`#ffd9a0`、`#bfeaff`→`#ffedc2`。
V3（青碧）：`bg` `#123b38 → #081b19`；`shellTop` `#e2fbf2 → #8fd8c4`；`shellBottom` `#4e9f8c → #2c6457`；扇脊 stroke `#5fa896`；泛光/亮核 `#7fffd4` / `#d8fff0`。

渲染（Chrome 不在则用 `qlmanage -t -s 1024` 兜底，透明背景需检查）：

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
S=/private/tmp/claude-501/-Users-kris-Documents-clamshell/84a7ad4f-d42b-4482-bc81-40441c204e0f/scratchpad
for v in v1 v2 v3; do
  "$CHROME" --headless=new --screenshot="$S/icon-$v.png" --window-size=1024,1024 \
    --default-background-color=00000000 --hide-scrollbars "file://$S/icon-$v.svg" 2>/dev/null
done
```

- [ ] **Step 2（主会话）: 选稿**

`open /private/tmp/claude-501/-Users-kris-Documents-clamshell/84a7ad4f-d42b-4482-bc81-40441c204e0f/scratchpad/icon-v1.png icon-v2.png icon-v3.png` 开 Preview → AskUserQuestion 让用户挑（或提出改色/改形，迭代后再选）。选定后把对应 SVG 存为 `app/AppIcon.svg`。

- [ ] **Step 3: 生成 icns**

```bash
cd /Users/kris/Documents/clamshell/app && rm -rf AppIcon.iconset && mkdir AppIcon.iconset
M=/private/tmp/claude-501/-Users-kris-Documents-clamshell/84a7ad4f-d42b-4482-bc81-40441c204e0f/scratchpad/icon-<选中版本>.png
for s in 16 32 128 256 512; do
  sips -z $s $s "$M" --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) "$M" --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf AppIcon.iconset && ls -la AppIcon.icns
```

Expected: `AppIcon.icns` 生成（≈几百 KB）。

- [ ] **Step 4: build-app.sh 接线**

① `cp "$BIN_PATH" ...` 之后加：

```bash
[ -f "AppIcon.icns" ] && cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
```

② Info.plist heredoc 里 `<key>CFBundleName</key>` 之前加两行：

```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

- [ ] **Step 5: 重装验证**

```bash
cd /Users/kris/Documents/clamshell/app && bash build-app.sh && sips -g pixelWidth "/Applications/Clamshell Mode.app/Contents/Resources/AppIcon.icns" | tail -1 && open -R "/Applications/Clamshell Mode.app"
```

Expected: icns 就位；Finder 高亮显示 App 且**图标为贝壳**（Finder 缓存偶尔顽固——`touch "/Applications/Clamshell Mode.app"` 可催刷新）。打开 App → About 页显示贝壳图标。

- [ ] **Step 6: Commit**

```bash
cd /Users/kris/Documents/clamshell && git add app/AppIcon.svg app/AppIcon.icns app/build-app.sh && git commit -m "feat: clamshell app icon (shell with glowing seam) wired into bundle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: README、部署同步、真机推送验证、DEV_NOTES、push

**Files:**
- Modify: `README.zh.md` / `README.md` / `DEV_NOTES.md` / `SESSION_LOG.md`
- 部署目标: `~/.hammerspoon/`（install.sh）

**Interfaces:**
- Consumes: Task 1–4 全部产物
- Produces: origin/main 最新；运行时 = 仓库

- [ ] **Step 1: README.zh.md 六处**（编辑前先 Read 当前文件核对行号）

① 功能 bullet：删 `- **iPhone 远程切回** 通过 Shortcuts SSH 一键关闭唤醒并立即睡眠`；`- **长时间合盖 iMessage 提醒**（可选），方便包里跑着别忘了` → `- **长时间合盖 Bark 推送提醒**（可选），方便包里跑着别忘了`
② 组件表：`| \`Clamshell Mode.app\` (SwiftUI) | 配置 GUI：状态检查、网络识别、所有可调项 |` → `| \`Clamshell Mode.app\` (SwiftUI) | 配置 GUI：状态检查、所有可调项 |`
③ Setup bullet → `- **Setup**：实时检测 Hammerspoon / sudoers 状态`
④ Settings bullet 中 `手机号、提醒延时（1–120 分钟）` → `Bark 提醒（device key + 延时阈值 + 测试推送）`
⑤ 删「### iPhone 远程切回睡眠」整节（保留其后的 ⚠️ 散热提示行，移到「菜单栏 / 快捷键」小节末尾）
⑥ 手动改配置 JSON 示例：`"phone": "+8613...",` → `"barkKey": "your-bark-device-key",`；示例块后加一行：`另有 lua-only 可选键 \`menuRefreshInterval\`（菜单栏状态自刷新间隔秒数，默认 15）。`

- [ ] **Step 2: README.md 平行六处**

① 删 `- **Remote sleep from iPhone** via a Shortcuts SSH command — disable awake-mode and sleep instantly`；iMessage bullet → `- **Optional Bark push reminder** when the lid has been closed for a long time, so you don't forget the laptop is still running in your bag`
② 组件表 → `| \`Clamshell Mode.app\` (SwiftUI) | Configurator GUI: status checks, all tunable options |`
③ Setup bullet → `- **Setup**: live status of Hammerspoon / sudoers`
④ Settings bullet 中 `phone number, reminder delay (1–120 min)` → `Bark reminder (device key + delay threshold + test push)`
⑤ 删「### Remote sleep from iPhone」整节（⚠️ 行保留，移到 Menu bar / hotkey 小节末尾）
⑥ JSON 示例 `"phone": "+1...",` → `"barkKey": "your-bark-device-key",` + 追加行 `There is also a lua-only optional key \`menuRefreshInterval\` (menu bar self-refresh seconds, default 15).`

- [ ] **Step 3: 部署同步**

```bash
cd /Users/kris/Documents/clamshell && ./install.sh
```

Expected: 全绿完成；结尾提示已是 Bark 文案。然后核对运行时与仓库一致、旧 config 保留：

```bash
diff ~/Documents/clamshell/clamshell.lua ~/.hammerspoon/clamshell.lua && echo "runtime == repo"
python3 -c "import json;c=json.load(open('$HOME/.hammerspoon/clamshell-config.json'));print('keys:',sorted(c))"
```

Expected: `runtime == repo`；keys 仍含旧 `phone`（无害残留，GUI 首次保存后消失）。菜单栏图标在、点击可切换（用户目视确认）。

- [ ] **Step 4（主会话，需用户配合）: 真机 Bark 验证**

用户 iPhone 装 Bark → GUI Settings 填真实 device key、开启用 → 点「发送测试推送」→ 显示「已发送」且 iPhone 收到横幅 → 点「保存并重载」→ 确认 `~/.hammerspoon/clamshell-config.json` 出现 `barkKey`、`phone` 消失。

- [ ] **Step 5: DEV_NOTES / SESSION_LOG**

DEV_NOTES.md：① 删两处「本目录当前不是 git 仓库…」改为「git 仓库（main，origin=GitHub KrisWonka/clamshell-mode-mac）」；② 功能状态节补 Bark 迁移/SSH 移除/图标/光标修复收编；③ Open items 更新：移除已完成项，加「旧克隆 ~/clamshell-mode-mac 及分支 fix/menubar-refresh-window-storm 已无孤本价值，可清理」「朋友机器待升级（git pull + ./install.sh）」。SESSION_LOG.md 顶部追加本轮条目（改了什么/为什么/待办）。

- [ ] **Step 6: Commit + push（用户已明确要求上传 GitHub）**

```bash
cd /Users/kris/Documents/clamshell && git add README.md README.zh.md DEV_NOTES.md SESSION_LOG.md && git commit -m "docs: Bark migration, SSH removal, troubleshooting-era READMEs; refresh dev notes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" && git push origin main && git log --oneline origin/main -3
```

Expected: push 成功，远端包含本轮全部 commit（含此前 ahead 的两个 spec commit）。
