import Foundation
import AppKit

enum IconRenderer {
    static let hsDir: String = NSString(string: "~/.hammerspoon").expandingTildeInPath

    static func regenerate(sleep sleepSym: String, awake awakeSym: String) {
        renderSymbol(sleepSym, to: "\(hsDir)/icon-sleep.png")
        renderSymbol(awakeSym, to: "\(hsDir)/icon-awake.png")
    }

    static func renderSymbol(_ name: String, to path: String, pointSize: CGFloat = 18) {
        guard let baseImg = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let img = baseImg.withSymbolConfiguration(config) ?? baseImg

        let scale: CGFloat = 2
        let pixelW = Int(pointSize * scale)
        let pixelH = Int(pointSize * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else { return }
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        img.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
