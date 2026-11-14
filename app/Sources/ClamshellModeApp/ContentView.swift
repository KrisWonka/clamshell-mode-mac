import SwiftUI

struct ContentView: View {
    @State private var config: ClamshellConfig = ClamshellConfig.load()
    @State private var showAbout = false

    var body: some View {
        SettingsView(config: $config)
            .frame(minWidth: 720, minHeight: 600)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { showAbout.toggle() } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("关于")
                    .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                        AboutView()
                    }
                }
            }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            Text("Clamshell Mode")
                .font(.title2).bold()
            Text("macOS 合盖不睡眠 + 亮度联动 + 合盖省电")
                .font(.callout)
                .foregroundColor(.secondary)
            Link("github.com/KrisWonka/clamshell-mode-mac",
                 destination: URL(string: "https://github.com/KrisWonka/clamshell-mode-mac")!)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 320)
    }
}
