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

    static var isHammerspoonRunning: Bool {
        !runShell("pgrep -lf Hammerspoon").isEmpty
    }

    static var isSudoersConfigured: Bool {
        runShell("/usr/bin/sudo -n /usr/bin/pmset -g 1>/dev/null 2>&1 && echo ok").contains("ok")
    }

    static func reloadHammerspoon() {
        _ = runShell("osascript -e 'quit app \"Hammerspoon\"' 2>/dev/null; sleep 1; pkill -x Hammerspoon 2>/dev/null; sleep 1; open -a Hammerspoon")
    }
}
