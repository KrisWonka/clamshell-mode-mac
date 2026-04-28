import Foundation

struct ClamshellConfig: Codable, Equatable {
    var phone: String = ""
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
