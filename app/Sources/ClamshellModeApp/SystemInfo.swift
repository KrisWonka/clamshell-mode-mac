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

    static var username: String {
        NSUserName()
    }

    static var localHostname: String {
        let h = runShell("scutil --get LocalHostName")
        return h.isEmpty ? "" : "\(h).local"
    }

    /// Returns (interfaceName, ipAddress) tuples for all active IPv4 addresses except loopback.
    static var networkAddresses: [(label: String, ip: String)] {
        var result: [(String, String)] = []
        let raw = runShell("ifconfig | awk '/^[a-z]/{iface=$1} /inet /{print iface, $2}'")
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count == 2, parts[1] != "127.0.0.1" else { continue }
            let iface = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            let ip = parts[1]
            let label = friendlyLabel(forInterface: iface, ip: ip)
            result.append((label, ip))
        }
        return result
    }

    private static func friendlyLabel(forInterface iface: String, ip: String) -> String {
        if ip.hasPrefix("172.20.10.") { return "iPhone 热点 (\(iface))" }
        if ip.hasPrefix("100.") { return "Tailscale (\(iface))" }
        if ip.hasPrefix("10.211.55.") { return "Parallels (\(iface))" }
        if ip.hasPrefix("10.37.129.") { return "Parallels (\(iface))" }
        if iface == "en0" || iface == "en1" { return "WiFi/有线 (\(iface))" }
        return "\(iface)"
    }

    static var isHammerspoonRunning: Bool {
        !runShell("pgrep -lf Hammerspoon").isEmpty
    }

    static var isSshEnabled: Bool {
        runShell("nc -z -w 1 localhost 22 2>&1 && echo yes").contains("yes")
    }

    static var isSudoersConfigured: Bool {
        runShell("/usr/bin/sudo -n /usr/bin/pmset -g 1>/dev/null 2>&1 && echo ok").contains("ok")
    }

    static var sleepDisabled: Bool {
        runShell("/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}'") == "1"
    }

    static func reloadHammerspoon() {
        _ = runShell("osascript -e 'quit app \"Hammerspoon\"' 2>/dev/null; sleep 1; open -a Hammerspoon")
    }

    static func openShortcutsApp() {
        NSWorkspace.shared.open(URL(string: "shortcuts://")!)
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
