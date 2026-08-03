import SwiftUI

struct ContentView: View {
    @State private var config: ClamshellConfig = ClamshellConfig.load()

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "wrench.and.screwdriver") }
            SettingsView(config: $config)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 720, minHeight: 600)
        .padding(.top, 4)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
            Text("Clamshell Mode")
                .font(.largeTitle).bold()
            Text("macOS 合盖不睡眠 + 智能亮度联动 + 远程切换")
                .foregroundColor(.secondary)
            Link("github.com/KrisWonka/clamshell-mode-mac",
                 destination: URL(string: "https://github.com/KrisWonka/clamshell-mode-mac")!)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
