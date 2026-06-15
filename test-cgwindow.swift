import Cocoa
import CoreGraphics

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
if let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for info in windowListInfo {
        let name = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
        let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if layer < 0 { continue }
        if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] {
            let x = boundsDict["X"]!
            let y = boundsDict["Y"]!
            let w = boundsDict["Width"]!
            let h = boundsDict["Height"]!
            print("Owner: \(name), PID: \(pid), layer: \(layer), bounds: \(x), \(y), \(w), \(h)")
        }
    }
}
