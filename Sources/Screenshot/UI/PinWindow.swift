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

    public override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        // 窗口缩放时强制 contentView 及其子视图重新布局，确保 SwiftUI 关闭按钮跟随窗口
        if let contentView = self.contentView {
            contentView.needsLayout = true
            contentView.layoutSubtreeIfNeeded()
            for subview in contentView.subviews {
                subview.needsLayout = true
                subview.layoutSubtreeIfNeeded()
            }
        }
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
    
    // 在窗口级别拦截滚轮/捏合事件，实现窗口缩放与透明度调整
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            if event.modifierFlags.contains(.command) {
                let delta = event.scrollingDeltaY
                let zoomFactor: CGFloat = delta > 0 ? 1.05 : 0.95
                resizeProportionally(by: zoomFactor)
                return
            } else {
                let delta = event.scrollingDeltaY
                let change = Double(delta) * 0.01
                let newAlpha = max(0.15, min(1.0, alphaValue + change))
                alphaValue = newAlpha
                return
            }
        } else if event.type == .magnify {
            let factor = 1.0 + event.magnification
            resizeProportionally(by: factor)
            return
        }
        super.sendEvent(event)
    }
    
    func resizeProportionally(by factor: CGFloat) {
        let newWidth = max(50, min(frame.width * factor, 3000))
        let newHeight = max(50, min(frame.height * factor, 3000))
        let newX = frame.origin.x - (newWidth - frame.width) / 2
        let newY = frame.origin.y - (newHeight - frame.height) / 2
        let newFrame = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        self.setFrame(newFrame, display: true, animate: false)
    }
}

/// 内容视图：作为 NSHostingController 的容器
class PinContentView: NSView {
    weak var pinWindow: PinWindow?
}

/// 置顶贴图管理器
public class PinManager {
    public static let shared = PinManager()

    private var pinWindows: [PinWindow] = []

    private init() {
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

    private var overflowCount: Int = 0

    /// 置顶钉住一张图片
    /// 排布策略：右上角为锚点，新贴图依次向右下方错开堆叠
    public func pin(image: CGImage, rect: CGRect? = nil) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let scale = screen.backingScaleFactor

        let finalRect: CGRect
        if let customRect = rect {
            finalRect = customRect
        } else {
            let w = CGFloat(image.width) / scale
            let h = CGFloat(image.height) / scale

            if pinWindows.isEmpty {
                overflowCount = 0
            }

            // 右上角锚点，新贴图依次向左下方错开 24pt 堆叠
            let margin: CGFloat = 40
            let stagger: CGFloat = 24
            let count = CGFloat(pinWindows.count)

            var x = screenFrame.maxX - w - margin - (count * stagger)
            var y = screenFrame.maxY - h - margin - (count * stagger)

            // 防止向左溢出屏幕
            if x < screenFrame.minX + margin {
                overflowCount += 1
                let wrapOffset = CGFloat(overflowCount * 24)
                x = screenFrame.maxX - w - margin - wrapOffset
                y = screenFrame.maxY - h - margin - wrapOffset
            }

            // 防止向下溢出屏幕
            if y < screenFrame.minY + margin {
                overflowCount += 1
                let wrapOffset = CGFloat(overflowCount * 24)
                x = screenFrame.maxX - w - margin - wrapOffset
                y = screenFrame.maxY - h - margin - wrapOffset
            }

            finalRect = CGRect(x: x, y: y, width: w, height: h)
        }

        let panel = PinWindow(
            contentRect: finalRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        let contentView = PinContentView(frame: finalRect)
        contentView.pinWindow = panel
        contentView.autoresizingMask = [.width, .height]

        let rootView = PinRootView(image: image, window: panel) { [weak panel] in
            panel?.closeWithAnimation()
        }

        let controller = NSHostingController(rootView: rootView)
        controller.view.frame = contentView.bounds
        controller.view.autoresizingMask = [.width, .height]
        contentView.addSubview(controller.view)

        panel.contentView = contentView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        pinWindows.append(panel)
        AppLogger.ui.debug("📌 [PinManager] 新增置顶贴图，当前总计: \(self.pinWindows.count)")
    }

    public func removeWindow(_ window: PinWindow) {
        pinWindows.removeAll { $0 === window }
        AppLogger.ui.debug("📌 [PinManager] 贴图已销毁，当前总计: \(self.pinWindows.count)")
    }

    public func closeAll() {
        for win in pinWindows {
            win.close()
        }
        pinWindows.removeAll()
        AppLogger.ui.debug("📌 [PinManager] 已清空所有贴图")
    }
}

/// 贴图 SwiftUI 视图
/// 注意：不添加 .clipShape，避免对已有圆角透明像素的窗口截图造成二次裁切边缘残留
struct PinRootView: View {
    let image: CGImage
    let window: PinWindow
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
    }
}
