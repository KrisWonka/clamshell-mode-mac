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
