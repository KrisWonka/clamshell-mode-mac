import Foundation
import CoreGraphics

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

let displayID = CGMainDisplayID()
let args = CommandLine.arguments

func getCurrent() -> Float {
    var b: Float = 0
    _ = DisplayServicesGetBrightness(displayID, &b)
    return b
}

func setNow(_ v: Float) {
    let clamped = max(0.0, min(1.0, v))
    _ = DisplayServicesSetBrightness(displayID, clamped)
}

if args.count >= 4 && args[1] == "fade" {
    guard let target = Float(args[2]), let duration = Double(args[3]) else {
        FileHandle.standardError.write("usage: setbrightness fade <0.0-1.0> <seconds>\n".data(using: .utf8)!)
        exit(1)
    }
    let start = getCurrent()
    let delta = target - start
    let fps = 60.0
    let totalFrames = max(1, Int(duration * fps))
    let frameInterval = duration / Double(totalFrames)
    let startTime = Date()
    for i in 1...totalFrames {
        let nextTick = startTime.addingTimeInterval(Double(i) * frameInterval)
        let now = Date()
        if nextTick > now {
            Thread.sleep(forTimeInterval: nextTick.timeIntervalSince(now))
        }
        let t = Float(i) / Float(totalFrames)
        setNow(start + delta * t)
    }
    setNow(target)
} else if args.count >= 2 {
    guard let v = Float(args[1]) else {
        FileHandle.standardError.write("usage: setbrightness <0.0-1.0> | fade <target> <seconds>\n".data(using: .utf8)!)
        exit(1)
    }
    setNow(v)
} else {
    print(getCurrent())
}
