import SwiftUI

struct SettingsView: View {
    @Binding var config: ClamshellConfig
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus { case idle, saving, saved, error(String) }

    var body: some View {
        Form {
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
                    Text("修饰键")
                    HStack {
                        ForEach(["ctrl", "alt", "cmd", "shift"], id: \.self) { mod in
                            Toggle(mod, isOn: Binding(
                                get: { config.hotkeyMods.contains(mod) },
                                set: { isOn in
                                    if isOn {
                                        if !config.hotkeyMods.contains(mod) { config.hotkeyMods.append(mod) }
                                    } else {
                                        config.hotkeyMods.removeAll { $0 == mod }
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    Spacer()
                }
                .disabled(!config.hotkeyEnabled)
                HStack {
                    Text("主键")
                    TextField("6", text: $config.hotkeyKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                }
                .disabled(!config.hotkeyEnabled)
            }

            Section("菜单栏图标") {
                IconPicker(label: "睡眠模式 (💤)", value: $config.iconSleep, suggestions: ["zzz", "moon", "moon.fill", "powersleep", "bed.double.fill"])
                IconPicker(label: "唤醒模式 (☕️)", value: $config.iconAwake, suggestions: ["cup.and.saucer.fill", "cup.and.saucer", "sun.max.fill", "bolt.fill", "powerplug.fill"])
                Text("可填任意 SF Symbol 名字（参考 Apple SF Symbols App）")
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
        DispatchQueue.global().async {
            do {
                try config.save()
                IconRenderer.regenerate(sleep: config.iconSleep, awake: config.iconAwake)
                SystemInfo.reloadHammerspoon()
                DispatchQueue.main.async {
                    saveStatus = .saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if case .saved = saveStatus { saveStatus = .idle }
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
