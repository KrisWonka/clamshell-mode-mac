import SwiftUI

struct SettingsView: View {
    @Binding var config: ClamshellConfig
    @State private var saveStatus: SaveStatus = .idle
    @State private var screenTimers = ScreenTimers(screensaverMin: 20, displaySleepBatteryMin: nil, displaySleepACMin: 0)
    @State private var loadedTimers: ScreenTimers? = nil   // 读入快照，diff 基准；nil = 尚未加载
    @State private var sudoOK = true

    enum SaveStatus { case idle, saving, saved, error(String) }

    var body: some View {
        Form {
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

            Section("亮度过渡") {
                Toggle("开盖渐亮", isOn: $config.fadeEnabled)
                HStack {
                    Text("过渡时长")
                    Slider(value: $config.fadeDuration, in: 0.3...5.0, step: 0.1)
                    Text("\(String(format: "%.1f", config.fadeDuration)) 秒")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!config.fadeEnabled)
            }

            Section("iMessage 长时间合盖提醒") {
                Toggle("启用", isOn: $config.notifyEnabled)
                HStack {
                    Text("手机号")
                    TextField("+8613812345678", text: $config.phone)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
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
            }

            Section("快捷键") {
                Toggle("启用全局快捷键", isOn: $config.hotkeyEnabled)
                HStack {
                    Text("组合键")
                    HotkeyRecorder(mods: $config.hotkeyMods, key: $config.hotkeyKey)
                }
                .disabled(!config.hotkeyEnabled)
                Text("点上方按钮 → 按一下组合键即可绑定（ESC 取消）。修饰键 ⌃⌥⇧⌘ 至少要有一个。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("菜单栏图标") {
                IconPicker(label: "睡眠模式 (💤)", value: $config.iconSleep, suggestions: ["zzz", "moon", "moon.fill", "powersleep", "bed.double.fill"])
                IconPicker(label: "唤醒模式 (☕️)", value: $config.iconAwake, suggestions: ["cup.and.saucer.fill", "cup.and.saucer", "sun.max.fill", "bolt.fill", "powerplug.fill"])
                Text("可填任意 SF Symbol 名字（参考 Apple SF Symbols App）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("屏幕中央提示文字") {
                HStack {
                    Text("睡眠模式 (💤)")
                        .frame(width: 130, alignment: .leading)
                    TextField("Clam Sleep", text: $config.alertSleep)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("唤醒模式 (☕️)")
                        .frame(width: 130, alignment: .leading)
                    TextField("Clam Awake", text: $config.alertAwake)
                        .textFieldStyle(.roundedBorder)
                }
                Text("切换合盖模式时，屏幕中央会闪现这段文字 1.5 秒")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("高级") {
                HStack {
                    Text("盖子状态轮询间隔")
                    Slider(value: $config.pollInterval, in: 0.5...5.0, step: 0.5)
                    Text("\(String(format: "%.1f", config.pollInterval)) 秒")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    statusBadge
                    Button("保存并重载") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    private func timerPicker(_ label: String, selection: Binding<Int>, base: [Int], loaded: Int?) -> some View {
        Picker(label, selection: selection) {
            ForEach(ScreenTimersIO.pickerOptions(base: base, current: loaded ?? 0), id: \.self) { m in
                Text(m == 0 ? "永不" : "\(m) 分钟").tag(m)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView().controlSize(.small)
        case .saved:
            Label("已保存", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red)
        }
    }

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
}

struct IconPicker: View {
    let label: String
    @Binding var value: String
    let suggestions: [String]

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 130, alignment: .leading)
            TextField("SF Symbol", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Image(systemName: value)
                .foregroundColor(.primary)
                .frame(width: 24)
            Menu("预设") {
                ForEach(suggestions, id: \.self) { sym in
                    Button { value = sym } label: {
                        Label(sym, systemImage: sym)
                    }
                }
            }
            .frame(maxWidth: 80)
        }
    }
}
