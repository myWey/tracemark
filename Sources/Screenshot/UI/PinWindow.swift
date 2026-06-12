import Cocoa
import SwiftUI

/// 置顶贴图窗口 Panel
public class PinWindow: NSPanel {
    
    public override var canBecomeKey: Bool { return true }
    public override var canBecomeMain: Bool { return true }
    
    public override func mouseDown(with event: NSEvent) {
        // 双击关闭贴图
        if event.clickCount == 2 {
            closeWithAnimation()
            return
        }
        // 调用系统拖拽方法移动窗口
        self.performDrag(with: event)
    }
    
    public override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        // 精细调节窗口透明度，透明度范围在 [0.15, 1.0]
        let change = Double(delta) * 0.01
        let newAlpha = max(0.15, min(1.0, self.alphaValue + change))
        self.alphaValue = newAlpha
    }
    
    public func closeWithAnimation() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.close()
            PinManager.shared.removeWindow(self)
        })
    }
}

/// 置顶贴图管理器
public class PinManager {
    public static let shared = PinManager()
    
    private var pinWindows: [PinWindow] = []
    
    private init() {
        // 应用退出前销毁所有贴图
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func handleAppTerminate() {
        closeAll()
    }
    
    public var hasPins: Bool {
        return !pinWindows.isEmpty
    }
    
    // 记录由于溢出导致的层叠次数
    private var overflowCount: Int = 0
    
    /// 置顶钉住一张图片
    public func pin(image: CGImage, rect: CGRect? = nil) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let scale = screen.backingScaleFactor
        
        let finalRect: CGRect
        if let customRect = rect {
            finalRect = customRect
        } else {
            // 贴图大小限制（最大不超过主屏幕可视区域的 35%）
            let maxW = screenFrame.width * 0.35
            let maxH = screenFrame.height * 0.35
            var w = CGFloat(image.width) / scale
            var h = CGFloat(image.height) / scale
            
            if w > maxW || h > maxH {
                let ratio = min(maxW / w, maxH / h)
                w *= ratio
                h *= ratio
            }
            
            if pinWindows.isEmpty {
                overflowCount = 0
            }
            
            // 贴在桌面右上角作为参考，顺序排布避免重叠
            var currentY: CGFloat = 40
            var currentX: CGFloat = 40
            var currentColumnWidth: CGFloat = 0
            
            // 遍历已有窗口，推演当前应在的位置
            for window in pinWindows {
                let winH = window.frame.height
                let winW = window.frame.width
                
                if currentY + winH > screenFrame.height - 40 {
                    currentY = 40
                    currentX += currentColumnWidth + 20
                    currentColumnWidth = 0
                }
                currentColumnWidth = max(currentColumnWidth, winW)
                currentY += winH + 20
            }
            
            // 为新窗口 (w, h) 计算位置
            if currentY + h > screenFrame.height - 40 {
                currentY = 40
                currentX += currentColumnWidth + 20
                currentColumnWidth = 0
            }
            
            // 如果溢出屏幕左侧边界，则回到右上角重叠在老图上，并带有一定偏移量保证可见性
            if screenFrame.maxX - currentX - w < screenFrame.minX + 40 {
                overflowCount += 1
                let offset = CGFloat(overflowCount * 24)
                currentX = 40 + offset
                currentY = 40 + offset
                
                // 播放满了的音效提示（音量调弱）
                if let sound = NSSound(named: "Basso") {
                    sound.volume = 0.2
                    sound.play()
                }
            }
            
            let x = screenFrame.maxX - w - currentX
            let y = screenFrame.maxY - h - currentY
            finalRect = CGRect(x: x, y: y, width: w, height: h)
        }
        
        let panel = PinWindow(
            contentRect: finalRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let rootView = PinRootView(image: image) { [weak panel] in
            panel?.closeWithAnimation()
        }.frame(width: finalRect.width, height: finalRect.height)
        
        let controller = NSHostingController(rootView: rootView)
        panel.contentViewController = controller
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        
        // 淡入显示
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
        
        pinWindows.append(panel)
        print("📌 [PinManager] 新增置顶贴图，当前总计: \(pinWindows.count)")
    }
    
    public func removeWindow(_ window: PinWindow) {
        pinWindows.removeAll { $0 === window }
        print("📌 [PinManager] 贴图已销毁，当前总计: \(pinWindows.count)")
    }
    
    public func closeAll() {
        for win in pinWindows {
            win.close()
        }
        pinWindows.removeAll()
        print("📌 [PinManager] 已清空所有贴图")
    }
}

/// 贴图 SwiftUI 视图
struct PinRootView: View {
    let image: CGImage
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 3)
                
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6).clipShape(Circle()))
                            .font(.system(size: 20))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hover
                }
            }
        }
    }
}
