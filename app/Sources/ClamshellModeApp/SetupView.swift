import SwiftUI

struct SetupView: View {
    @State private var hsRunning = SystemInfo.isHammerspoonRunning
    @State private var sshOn = SystemInfo.isSshEnabled
    @State private var sudoersOk = SystemInfo.isSudoersConfigured
    @State private var addresses: [(label: String, ip: String)] = SystemInfo.networkAddresses
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
                macShortcutCard
                iphoneSetupCard
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
            let s = SystemInfo.isSshEnabled
            let su = SystemInfo.isSudoersConfigured
            let a = SystemInfo.networkAddresses
            DispatchQueue.main.async {
                hsRunning = h
                sshOn = s
                sudoersOk = su
                addresses = a
                refreshing = false
            }
        }
    }

    private var statusCard: some View {
        GroupBox(label: Label("系统状态", systemImage: "checkmark.seal")) {
            VStack(alignment: .leading, spacing: 6) {
                statusRow("Hammerspoon 运行中", hsRunning, hint: hsRunning ? nil : "启动 Hammerspoon")
                statusRow("Remote Login (SSH)", sshOn, hint: sshOn ? nil : "去 系统设置 → 通用 → 共享 → 远程登录 打开")
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

    private var macShortcutCard: some View {
        GroupBox(label: Label("Mac 快捷指令", systemImage: "command")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("名为「**Stop Awake**」的 Shortcut，跑这一行：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                CodeBlock(text: "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/pmset sleepnow")
                HStack {
                    Button("复制脚本") {
                        SystemInfo.copyToClipboard("/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/pmset sleepnow")
                    }
                    Button("打开快捷指令 App") {
                        SystemInfo.openShortcutsApp()
                    }
                    Spacer()
                    Text("操作：➕ → 「运行 Shell 脚本」→ 粘贴 → 命名 Stop Awake")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var iphoneSetupCard: some View {
        GroupBox(label: Label("iPhone 远程触发设置", systemImage: "iphone")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("用 iPhone Shortcuts 的「通过 SSH 运行脚本」动作，填以下信息：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                infoRow("用户名 (User)", value: SystemInfo.username)
                infoRow("端口 (Port)", value: "22")
                infoRow("脚本", value: "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/pmset sleepnow", multiline: true)

                Divider().padding(.vertical, 4)

                Text("**主机 (Host)** —— 不同网络环境用不同地址：")
                    .font(.caption)
                infoRow("Bonjour", value: SystemInfo.localHostname, hint: "同 WiFi 局域网用，热点环境一般失败")
                ForEach(addresses, id: \.ip) { addr in
                    infoRow(addr.label, value: addr.ip, hint: addr.ip.hasPrefix("100.") ? "Tailscale 推荐 — 跨网络也能用" : nil)
                }
            }
            .padding(8)
        }
    }

    private func infoRow(_ label: String, value: String, hint: String? = nil, multiline: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.body, design: .default))
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if multiline {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                } else {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let hint = hint {
                    Text(hint).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button { SystemInfo.copyToClipboard(value) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制")
        }
    }
}

struct CodeBlock: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
    }
}
