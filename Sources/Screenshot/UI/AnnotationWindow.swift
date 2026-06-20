import Cocoa
import SwiftUI

/// 标注专用的无边框悬浮卡片窗口
class AnnotationWindow: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

/// 标注画布管理器
public class AnnotationManager {
    public static let shared = AnnotationManager()
    private var window: NSPanel?
    
    private init() {
        // 监听进入标注的通知
        NotificationCenter.default.addObserver(
            forName: .openAnnotationCanvas,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            AppLogger.ui.debug("🔔 [AnnotationManager] 收到 OpenAnnotationCanvas 通知，准备拉起标注画布...")
            if let userInfo = notification.userInfo {
                guard let cfValue = userInfo["image"] as? CFTypeRef,
                      CFGetTypeID(cfValue) == CGImage.typeID else {
                    AppLogger.ui.error("❌ [AnnotationManager] 通知 userInfo 中未携带 CGImage 对象！")
                    return
                }
                let image = cfValue as! CGImage  // CFGetTypeID 已校验，安全
                let recordId = userInfo["recordId"] as? UUID
                let annotations: [AnnotationItem]
                if let data = userInfo["annotationsData"] as? Data {
                    annotations = (try? JSONDecoder().decode([AnnotationItem].self, from: data)) ?? []
                } else {
                    annotations = userInfo["annotations"] as? [AnnotationItem] ?? []
                }
                self?.showAnnotationCanvas(for: image, initialAnnotations: annotations, recordId: recordId)
            } else if let obj = notification.object {
                guard let cfValue = obj as? CFTypeRef,
                      CFGetTypeID(cfValue) == CGImage.typeID else {
                    AppLogger.ui.error("❌ [AnnotationManager] 通知 object 未携带 CGImage 对象！")
                    return
                }
                let image = cfValue as! CGImage  // CFGetTypeID 已校验，安全
                self?.showAnnotationCanvas(for: image)
            } else {
                AppLogger.ui.error("❌ [AnnotationManager] 通知中未携带 CGImage 对象！")
            }
        }
    }
    
    /// 拉起居中的标注画布窗口
    public func showAnnotationCanvas(for image: CGImage, initialAnnotations: [AnnotationItem] = [], recordId: UUID? = nil) {
        // 防御性清理
        window?.orderOut(nil)
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let scaleFactor = screen.backingScaleFactor
        
        // 计算图片在屏幕上的最佳展示尺寸（留出一定边距）
        let imageWidth = CGFloat(image.width) / scaleFactor
        let imageHeight = CGFloat(image.height) / scaleFactor
        
        // 加上工具栏所需的额外高度 (预留 120pt 给多行工具栏和边距)，且宽度不小于工具栏最低要求宽度
        let windowWidth = max(imageWidth, 850)
        let windowHeight = imageHeight + 120
        
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.midY - windowHeight / 2
        let rect = CGRect(x: x, y: y, width: windowWidth, height: windowHeight)
        let controller = NSHostingController(rootView: AnnotationRootView(
            image: image,
            displaySize: CGSize(width: imageWidth, height: imageHeight),
            initialAnnotations: initialAnnotations,
            recordId: recordId,
            onClose: { [weak self] in
                self?.close()
            }
        ))
        
        let panel = AnnotationWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let titleKey = recordId != nil ? "历史标注再编辑" : "标注与编辑"
        panel.title = LanguageManager.shared.localizedString(forKey: titleKey)
        panel.contentViewController = controller
        panel.isFloatingPanel = false
        panel.level = NSWindow.Level.normal
        panel.isMovableByWindowBackground = true
        
        // 强制尺寸
        controller.view.frame = NSRect(origin: .zero, size: rect.size)
        panel.setContentSize(rect.size)
        panel.setFrame(rect, display: true)
        
        // 激活动画
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
        
        self.window = panel
    }
    
    public func close() {
        guard let panel = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            self.window = nil
        })
    }
}
