import Cocoa
import CoreGraphics

public struct WindowInfo {
    public let rect: CGRect
    public let level: Int
    public let layer: Int
    public let windowID: CGWindowID
}

public class WindowSnapper {
    
    /// 获取屏幕上所有可见窗口的信息
    public static func getVisibleWindows(on screen: NSScreen) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        var windows: [WindowInfo] = []
        let screenFrame = screen.frame
        
        for info in windowListInfo {
            // 获取 PID 并过滤掉当前应用的窗口
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            if pid == ProcessInfo.processInfo.processIdentifier {
                continue
            }
            
            // 过滤不可见或全透明的窗口
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 {
                continue
            }
            
            // 获取窗口层级
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            
            // 绝大多数标准应用程序窗口的 Layer 为 0。
            // 过滤掉非 0 的层级（如 Dock 会创建一个不可见的全屏 Layer 20 窗口，Window Server 的菜单栏等）
            if layer != 0 {
                continue
            }
            
            // 获取窗口 Bounds (在 CG 坐标系中，原点在主屏左上角)
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }
            
            let cgRect = CGRect(x: x, y: y, width: width, height: height)
            
            // 我们需要将 CG 坐标系的 cgRect 转换到当前屏幕的局部坐标系
            // 这样它才能与 SwiftUI 的坐标系匹配
            // CG 坐标系：(0,0) 在主屏左上角，Y轴向下
            // NSScreen 坐标系：(0,0) 在主屏左下角，Y轴向上
            // 但是我们的 OverlayRootView 使用的是 top-left 为原点的局部坐标系
            
            // 首先，将 CG 的坐标转为 Cocoa 全局坐标
            // 主屏的高度用来翻转 Y
            guard let primaryScreen = NSScreen.screens.first else { continue }
            let cocoaGlobalY = primaryScreen.frame.height - cgRect.origin.y - cgRect.height
            let cocoaGlobalRect = CGRect(x: cgRect.origin.x, y: cocoaGlobalY, width: cgRect.width, height: cgRect.height)
            
            // 检查窗口是否与当前屏幕相交
            if !cocoaGlobalRect.intersects(screenFrame) {
                continue
            }
            
            // 将 Cocoa 全局坐标转换为当前屏幕的局部坐标 (Bottom-Left)
            let localBottomLeftRect = CGRect(
                x: cocoaGlobalRect.origin.x - screenFrame.origin.x,
                y: cocoaGlobalRect.origin.y - screenFrame.origin.y,
                width: cocoaGlobalRect.width,
                height: cocoaGlobalRect.height
            )
            
            // 最后，转换为 SwiftUI (Top-Left) 坐标系
            let localTopLeftRect = CGRect(
                x: localBottomLeftRect.origin.x,
                y: screenFrame.height - localBottomLeftRect.origin.y - localBottomLeftRect.height,
                width: localBottomLeftRect.width,
                height: localBottomLeftRect.height
            )
            
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            
            windows.append(WindowInfo(rect: localTopLeftRect, level: 0, layer: layer, windowID: windowID))
        }
        
        return windows
    }
}
