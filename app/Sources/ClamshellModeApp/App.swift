import SwiftUI

@main
struct ClamshellModeAppMain: App {
    var body: some Scene {
        WindowGroup("Clamshell Mode") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
