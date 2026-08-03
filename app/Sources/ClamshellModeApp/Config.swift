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
