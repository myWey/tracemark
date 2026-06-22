import Cocoa
import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers
import Translation

public enum PostCaptureAction: String {
    case none
    case ocr
    case translate
    case copyToAI
}

/// 为窗口截图应用圆角透明遮罩，去除 macOS 窗口圆角外的背景残留。
/// 使用 premultiplied ARGB context + clip 绘制，圆角外区域保持 RGBA 全 0，避免复制到外部应用时出现白边。
/// - Parameter inset: 向内收缩像素，用于裁掉圆角边缘的半透明白色残留；fallback 去背景时默认 3，最终输出时建议 1。
func applyWindowCornerMask(to image: CGImage, cornerRadius: CGFloat, inset: CGFloat = 3.0) -> CGImage? {
    let width = image.width
    let height = image.height
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    // 创建 premultiplied ARGB context，初始完全透明黑色（RGBA 全 0）
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    // 先清空为透明
    ctx.clear(rect)

    // 绘制圆角裁切路径，向内收缩以裁掉 macOS 窗口边缘的白色残留像素
    let insetRect = rect.insetBy(dx: inset, dy: inset)
    let insetRadius = max(0, cornerRadius - inset)
    let path = CGPath(roundedRect: insetRect, cornerWidth: insetRadius, cornerHeight: insetRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // 在 clip 区域内绘制原图
    ctx.draw(image, in: rect)

    // 强制 premultiplied alpha，确保透明区域 RGB 归零，避免外部应用显示白边
    guard let masked = ctx.makeImage() else { return nil }
    return ensurePremultipliedAlpha(for: masked) ?? masked
}

/// 将图片绘制到 premultiplied ARGB 透明上下文，强制透明区域的 RGB 归零。
/// 修复部分渲染路径（如 ImageRenderer）可能将透明像素写成 RGBA(1,1,1,0) 的问题，
/// 避免复制到微信等外部应用时圆角外出现白色残留。
func ensurePremultipliedAlpha(for image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    ctx.clear(rect)
    ctx.draw(image, in: rect)
    return ctx.makeImage()
}

/// 仅对图像边缘区域做 alpha 阈值清理：alpha 低于阈值的像素强制设为全透明。
/// 用于清除窗口截图圆角及四边残留的半透明白色像素，避免复制到微信等外部应用时显示白边。
func thresholdAlphaEdge(for image: CGImage, edgeWidth: Int = 20, threshold: UInt8 = 32) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let space = image.colorSpace else { return nil }
    let bitmapInfo = image.bitmapInfo.rawValue
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: space,
        bitmapInfo: bitmapInfo
    ) else { return nil }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.draw(image, in: rect)

    // 根据 alpha 位置确定偏移（premultipliedFirst/Last + byteOrder）
    let alphaInfo = image.alphaInfo
    let isLittleEndian = (bitmapInfo & CGBitmapInfo.byteOrderMask.rawValue) == CGBitmapInfo.byteOrder32Little.rawValue
    let alphaOffset: Int
    switch alphaInfo {
    case .premultipliedFirst, .first, .noneSkipFirst:
        alphaOffset = isLittleEndian ? 3 : 0
    case .premultipliedLast, .last, .noneSkipLast:
        alphaOffset = isLittleEndian ? 0 : 3
    default:
        return nil
    }

    let edge = min(edgeWidth, min(width, height) / 2)
    guard edge > 0 else { return ctx.makeImage() }

    for y in 0..<height {
        let isTopEdge = y < edge
        let isBottomEdge = y >= height - edge
        for x in 0..<width {
            let isLeftEdge = x < edge
            let isRightEdge = x >= width - edge
            guard isTopEdge || isBottomEdge || isLeftEdge || isRightEdge else { continue }

            let pixelOffset = y * bytesPerRow + x * bytesPerPixel
            if pixels[pixelOffset + alphaOffset] < threshold {
                pixels[pixelOffset] = 0
                pixels[pixelOffset + 1] = 0
                pixels[pixelOffset + 2] = 0
                pixels[pixelOffset + 3] = 0
            }
        }
    }

    guard let newCtx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: space,
        bitmapInfo: bitmapInfo
    ) else { return nil }

    return newCtx.makeImage()
}

/// 将 `maskImage` 的 alpha 通道作为透明度蒙版应用到 `image` 上。
/// 用于标注渲染后恢复窗口截图原有的圆角透明区域，避免 ImageRenderer 等路径在角落填充白色。
func applyAlphaMask(from maskImage: CGImage, to image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    guard width == maskImage.width, height == maskImage.height else { return nil }
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    ctx.clear(rect)
    ctx.draw(image, in: rect)
    // 使用 destinationIn 混合模式：保留 image 中对应 maskImage 不透明区域的像素，
    // 其余区域（maskImage 透明）变为透明
    ctx.setBlendMode(.destinationIn)
    ctx.draw(maskImage, in: rect)
    return ctx.makeImage()
}

/// 自定义遮罩窗口，重写使其可成为 Key/Main 窗口以接收键盘/鼠标事件 (P3)
class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

/// 支持第一响应的 SwiftUI 宿主视图
class TrackingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// 完全接管系统底层鼠标事件的视图，无视任何键盘修饰键（如按住 Command 时拖拽不会失效）
struct MouseTrackingView: NSViewRepresentable {
    let onDragStart: (CGPoint, Int) -> Void
    let onDragChange: (CGPoint) -> Void
    let onDragEnd: () -> Void
    let onCancel: () -> Void
    var onHover: ((CGPoint) -> Void)? = nil
    var onHoverExited: (() -> Void)? = nil
    var activeTool: AnnotationToolType = .rectangle
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    // 用于在 MouseTrackingView 内部检测双击序号圆圈，绕过 SwiftUI 手势被 NSView 拦截的问题
    var annotations: [AnnotationItem] = []
    var mapPoint: ((CGPoint) -> CGPoint)? = nil

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onDown = onDragStart
        view.onDrag = onDragChange
        view.onUp = onDragEnd
        view.onCancel = onCancel
        view.onHover = onHover
        view.onHoverExited = onHoverExited
        view.activeTool = activeTool
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onDelete = onDelete
        view.annotations = annotations
        view.mapPoint = mapPoint
        return view
    }
    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onHoverExited = onHoverExited
        nsView.onDown = onDragStart
        nsView.onDrag = onDragChange
        nsView.onUp = onDragEnd
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onDelete = onDelete
        nsView.annotations = annotations
        nsView.mapPoint = mapPoint
        if nsView.activeTool != activeTool {
            nsView.activeTool = activeTool
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
}

class TrackingNSView: NSView {
    var onDown: ((CGPoint, Int) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onUp: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHover: ((CGPoint) -> Void)?
    var onHoverExited: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDelete: (() -> Void)?
    var activeTool: AnnotationToolType = .rectangle
    var annotations: [AnnotationItem] = []
    var mapPoint: ((CGPoint) -> CGPoint)? = nil

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }
    override var isFlipped: Bool { return true }
    override var mouseDownCanMoveWindow: Bool { return false }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NotificationCenter.default.addObserver(forName: .selectedToolChanged, object: nil, queue: .main) { [weak self] notification in
                if let tool = notification.object as? AnnotationToolType {
                    self?.activeTool = tool
                    if let selfView = self {
                        self?.window?.invalidateCursorRects(for: selfView)
                    }
                }
            }
        }
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        let isBrush = activeTool == .pencil || activeTool == .highlighter || activeTool == .blur || activeTool == .mosaic
        if isBrush {
            self.addCursorRect(self.bounds, cursor: NSCursor.transparent)
        } else {
            self.addCursorRect(self.bounds, cursor: NSCursor.crosshair)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)
    }
    
    override func mouseExited(with event: NSEvent) {
        onHoverExited?()
    }
    
    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmd = modifierFlags.contains(.command)
        let isShift = modifierFlags.contains(.shift)
        
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
            return
        } else if isCmd && event.keyCode == 6 {
            if isShift {
                onRedo?()
            } else {
                onUndo?()
            }
            return
        } else if event.keyCode == 53 {
            onCancel?()
            return
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if self.window?.firstResponder != self {
            self.window?.makeFirstResponder(self)
        }
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)

        // 双击时直接在 MouseTrackingView 内部检测是否命中序号圆圈，
        // 绕开 SwiftUI 手势被 NSView 拦截的问题。
        if event.clickCount >= 2, let mapPoint = mapPoint {
            let localPoint = mapPoint(point)
            for item in annotations.reversed() where item.type == .numberedText || item.type == .counter {
                let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.doubleTapHitMultiplier
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(localPoint) {
                    NotificationCenter.default.post(name: .counterDoubleTapped, object: item.id)
                    return
                }
            }
        }

        onDown?(point, event.clickCount)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)
        onDrag?(point)
    }
    
    override func mouseUp(with event: NSEvent) {
        onUp?()
    }
}

/// 悬浮遮罩管理器，控制所有屏幕的截图遮罩窗口
public class OverlayManager {
    public static let shared = OverlayManager()
    private var windows: [NSWindow] = []
    
    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if !(self?.windows.isEmpty ?? true) {
                AppLogger.ui.debug("ℹ️ [OverlayManager] 应用失去焦点，自动取消截图")
                self?.closeAll()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] notification in
            if let win = notification.object as? NSWindow, let self = self {
                if self.windows.contains(win) {
                    DispatchQueue.main.async {
                        if !self.windows.contains(where: { $0.isKeyWindow }) {
                            AppLogger.ui.debug("ℹ️ [OverlayManager] 遮罩窗口失去焦点，自动取消截图")
                            self.closeAll()
                        }
                    }
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                if !(self?.windows.isEmpty ?? true) {
                    AppLogger.ui.debug("ℹ️ [OverlayManager] 其他应用被激活 (\(app.localizedName ?? "")), 自动取消截图")
                    self?.closeAll()
                }
            }
        }
    }
    
    /// 唤起全屏截图遮罩
    private var escMonitor: Any?
    private var escGlobalMonitor: Any?
    private var onCanceledCallback: (() -> Void)?
    public func showOverlay(captures: [ScreenCapture], onCaptured: @escaping (CGImage, CGImage?, [AnnotationItem]?, NSScreen, PostCaptureAction) -> Void, canceled: @escaping () -> Void) {
        AppLogger.ui.debug("ℹ️ [OverlayManager] 开始唤起 \(captures.count) 个遮罩窗口...")
        closeAll() // 防御性清理
        
        // 注册全局 ESC 键监听
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC 键
                AppLogger.ui.debug("ℹ️ [OverlayManager] 监听到全局 ESC 键，取消截图")
                DispatchQueue.main.async {
                    canceled()
                    self?.closeAll()
                }
                return nil // 拦截事件，不再继续传递
            }
            return event
        }
        
        // 针对焦点丢失情况，补充 Global Monitor (仅在其他应用激活时生效)
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC 键
                AppLogger.ui.debug("ℹ️ [OverlayManager] (Global) 监听到 ESC 键，取消截图")
                DispatchQueue.main.async {
                    canceled()
                    self?.closeAll()
                }
            }
        }
        
        for capture in captures {
            let screen = capture.screen
            let screenFrame = screen.frame
            
            AppLogger.ui.debug("ℹ️ [OverlayManager] 屏幕信息 - frame: \(String(describing: screenFrame)), visibleFrame: \(String(describing: screen.visibleFrame)), backingScaleFactor: \(screen.backingScaleFactor)")
            
            let loc = NSEvent.mouseLocation
            let x = loc.x - screenFrame.minX
            let y = screenFrame.maxY - loc.y
            let initialHover = CGPoint(x: x, y: y)
            
            let rootView = OverlayRootView(capture: capture, initialHoverPoint: initialHover, onCaptured: { image, cleanImage, annotations, action in
                AppLogger.ui.debug("ℹ️ [OverlayManager] 遮罩层触发 onCaptured，开始执行回调...")
                onCaptured(image, cleanImage, annotations, screen, action)
                self.closeAll()
            }, onCanceled: {
                AppLogger.ui.debug("ℹ️ [OverlayManager] 遮罩层触发 onCanceled...")
                canceled()
                self.closeAll()
            })
            
            // 将 canceled 回调保存起来供 didResignActive 使用
            self.onCanceledCallback = canceled
            
            let hostingView = TrackingHostingView(rootView: rootView.applyAppLanguage())
            hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
            
            let window = CaptureOverlayWindow(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel], // 恢复 .nonactivatingPanel 以避免抢焦点但保证能收到事件
                backing: .buffered,
                defer: false,
                screen: screen
            )
            
            // 先配置窗口属性
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.5) // 临时用半透明黑测试可见性
            window.isOpaque = false
            window.hasShadow = false
            window.animationBehavior = .none // 防止 Apple 芯片上的闪烁动效
            window.isFloatingPanel = true
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // 设置内容
            window.contentView = hostingView
            
            // 强制设置 frame 和内容尺寸
            window.setContentSize(screenFrame.size)
            window.setFrame(screenFrame, display: true)
            
            AppLogger.ui.debug("ℹ️ [OverlayManager] 窗口属性 - frame: \(String(describing: window.frame)), contentView.bounds: \(String(describing: window.contentView?.bounds ?? .zero)), hostingView.frame: \(String(describing: hostingView.frame))")
            
            // 激活应用并显示窗口（不调用 NSApp.activate 以避免非必要的主屏幕切换）
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            // 验证窗口状态
            AppLogger.ui.debug("ℹ️ [OverlayManager] 窗口状态 - isVisible: \(window.isVisible), isKeyWindow: \(window.isKeyWindow), isMainWindow: \(window.isMainWindow), level: \(window.level.rawValue), windowNumber: \(window.windowNumber)")
            AppLogger.ui.debug("ℹ️ [OverlayManager] contentView - frame: \(String(describing: window.contentView?.frame ?? .zero)), isHidden: \(window.contentView?.isHidden ?? true)")
            
            windows.append(window)
        }
        
        AppLogger.ui.debug("ℹ️ [OverlayManager] 窗口创建完毕，当前持有窗口数: \(self.windows.count)")
    }
    
    /// 关闭所有遮罩窗口
    public func closeAll() {
        AppLogger.ui.debug("ℹ️ [OverlayManager] 执行 closeAll，当前窗口数: \(self.windows.count)")
        
        if !self.windows.isEmpty {
            self.onCanceledCallback?()
            self.onCanceledCallback = nil
        }
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        
        if let gMonitor = escGlobalMonitor {
            NSEvent.removeMonitor(gMonitor)
            escGlobalMonitor = nil
        }
        for window in self.windows {
            // 先尝试 orderOut，再 close，确保彻底从屏幕和内存移除
            window.orderOut(nil)
            window.close()
        }
        self.windows.removeAll()
        AppLogger.ui.info("✅ [OverlayManager] 遮罩窗口已全部销毁")
    }
}

/// 奇偶环绕规则挖空遮罩，用于在半透明背景中挖出亮色选区
struct InverseRectangle: Shape {
    let subRect: CGRect?
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let subRect = subRect {
            path.addRect(subRect)
        }
        return path
    }
}

enum CaptureSessionState {
    case cropping
    case editing
}



/// 全屏选区遮罩 SwiftUI 视图 (Unified Capture Session)
struct OverlayRootView: View {
    let capture: ScreenCapture
    let onCaptured: (CGImage, CGImage?, [AnnotationItem]?, PostCaptureAction) -> Void
    let onCanceled: () -> Void
    
    @StateObject private var editModel: AnnotationEditViewModel

    init(capture: ScreenCapture, initialHoverPoint: CGPoint, onCaptured: @escaping (CGImage, CGImage?, [AnnotationItem]?, PostCaptureAction) -> Void, onCanceled: @escaping () -> Void) {
        self.capture = capture
        self.onCaptured = onCaptured
        self.onCanceled = onCanceled
        self._editModel = StateObject(wrappedValue: AnnotationEditViewModel(
            annotations: [],
            behavior: .overlayConfig,
            selectedTool: .rectangle,
            hoverPoint: initialHoverPoint
        ))
    }

    @State private var sessionState: CaptureSessionState = .cropping

    // 窗口吸附状态
    @State private var availableWindows: [WindowInfo] = []
    @State private var hoverWindowRect: CGRect? = nil
    @State private var hoverWindowID: CGWindowID? = nil

    // 裁剪框状态
    @State private var startPoint: CGPoint? = nil
    @State private var currentPoint: CGPoint? = nil
    @State private var finalRect: CGRect? = nil

    // 裁剪框调整状态
    @State private var activeHandle: DragHandle? = nil
    @State private var initialRectBeforeDrag: CGRect? = nil
    @State private var dragStartPoint: CGPoint? = nil

    @State private var hasCaptured: Bool = false
    
    /// 动态计算选区
    var selectedRect: CGRect? {
        if sessionState == .editing {
            return finalRect
        }
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. 底层：冻结的全屏图片
                Image(decorative: capture.image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onTapGesture(perform: editModel.commitAllEdits)
                
                // 2. 标注层
                AnnotationCanvasLayer(
                    image: capture.image,
                    displaySize: CGSize(width: geometry.size.width, height: geometry.size.height),
                    annotations: editModel.annotations,
                    currentAnnotation: editModel.currentAnnotation,
                    selectedAnnotationId: editModel.selectedAnnotationId,
                    editingTextId: editModel.editingTextId,
                    editingCounterId: editModel.editingCounterId,
                    onTextChanged: handleTextChanged,
                    onTextCommit: editModel.commitAllEdits,
                    onCounterChanged: handleCounterChanged,
                    onSizeChanged: handleSizeChanged,
                    clipRect: finalRect
                )
                
                // 3. 中层：半透明变暗背景（裁剪和编辑态都显示，选区内挖空，选区外变暗）
                if let selectedRect = selectedRect {
                    InverseRectangle(subRect: selectedRect)
                        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false) // 让事件穿透
                }
                
                // 3.5 窗口吸附高亮层
                if sessionState == .cropping, selectedRect == nil, let hoverRect = hoverWindowRect {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.blue.opacity(0.8), lineWidth: 2)
                            .background(Color.blue.opacity(0.1))
                            .frame(width: hoverRect.width, height: hoverRect.height)
                            .position(x: hoverRect.midX, y: hoverRect.midY)
                        
                        // 左上角显示像素规格
                        Text("\(Int(hoverRect.width)) × \(Int(hoverRect.height))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .position(x: hoverRect.minX + 45, y: max(15, hoverRect.minY + 15))
                    }
                    .allowsHitTesting(false)
                }
                
                // 4. 选区边框与尺寸标签
                if let rect = selectedRect {
                    // 蓝色精致边框：始终显示，文本编辑时不隐藏，避免用户无法区分选区内外
                    Rectangle()
                        .stroke(Color.blue.opacity(sessionState == .cropping ? 1.0 : 0.8), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                    
                    if sessionState == .cropping {
                        // 实时大小气泡标签
                        Text("\(Int(rect.width)) × \(Int(rect.height))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.85))
                            .cornerRadius(4)
                            .offset(x: rect.minX, y: rect.minY - 26) // 显示在选区上方
                    } else {
                        // 绘制 8 个控制柄
                        ForEach(DragHandle.allCases, id: \.self) { handle in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .position(handlePosition(for: handle, rect: rect))
                                .allowsHitTesting(false)
                        }
                    }
                }
                // 5. 事件接收层
                
                // 隐藏的撤销重做按钮
                Button("") { editModel.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .frame(width: 0, height: 0)
                Button("") { editModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .opacity(0)
                    .allowsHitTesting(false)
                    .frame(width: 0, height: 0)
                
                MouseTrackingView(
                    onDragStart: handleDragStart,
                    onDragChange: handleDragChange,
                    onDragEnd: handleDragEnd,
                    onCancel: {
                        guard !hasCaptured else { return }
                        if sessionState == .editing {
                            // 退出编辑回到裁剪状态
                            sessionState = .cropping
                            finalRect = nil
                            startPoint = nil
                            currentPoint = nil
                            editModel.annotations.removeAll()
                            activeHandle = nil
                        } else {
                            onCanceled()
                        }
                    },
                    onHover: { pt in
                        if sessionState == .editing {
                            if let rect = finalRect, rect.contains(pt) {
                                editModel.hoverPoint = pt
                                editModel.isHoveringCanvas = true
                                handleHover(pt)
                            } else {
                                editModel.isHoveringCanvas = false
                                NSCursor.arrow.set()
                            }
                        } else {
                            editModel.hoverPoint = pt
                            editModel.isHoveringCanvas = true
                            handleHover(pt)
                            if editModel.selectedTool == .pencil || editModel.selectedTool == .highlighter || editModel.selectedTool == .blur || editModel.selectedTool == .mosaic {
                                NSCursor.transparent.set()
                            } else {
                                NSCursor.crosshair.set()
                            }
                        }
                    },
                    onHoverExited: {
                        editModel.isHoveringCanvas = false
                        NSCursor.arrow.set()
                    },
                    activeTool: editModel.selectedTool,
                    onUndo: editModel.undo,
                    onRedo: editModel.redo,
                    onDelete: editModel.deleteSelectedAnnotation,
                    annotations: editModel.annotations,
                    mapPoint: { $0 }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(editModel.editingTextId == nil && editModel.editingCounterId == nil)

                // 6. 悬浮工具栏 (仅在编辑状态下显示)
                if sessionState == .editing, let rect = finalRect {
                    let expectedWidth: CGFloat = 860.0
                    let toolbarWidth = min(expectedWidth, geometry.size.width - 24.0) // 确保不超屏幕
                    let toolbarHeight: CGFloat = 90.0
                    let padding: CGFloat = 12.0
                    
                    let tbX = max(toolbarWidth / 2 + padding, min(geometry.size.width - toolbarWidth / 2 - padding, rect.midX))
                    let spaceBelow = geometry.size.height - rect.maxY
                    let tbY: CGFloat = (spaceBelow < toolbarHeight + padding * 2) ? max(toolbarHeight / 2 + padding, rect.minY - padding - toolbarHeight / 2) : rect.maxY + padding + toolbarHeight / 2
                    
                    UnifiedToolbarView(
                        selectedTool: $editModel.selectedTool,
                        selectedColor: $editModel.selectedColor,
                        selectedFontSize: $editModel.selectedFontSize,
                        selectedLineWidth: $editModel.selectedLineWidth,
                        selectedBrushSize: $editModel.selectedBrushSize,
                        selectedTextStyle: $editModel.selectedTextStyle,
                        hasUndo: !editModel.undoStack.isEmpty,
                        hasRedo: !editModel.redoStack.isEmpty,
                        hasSelection: editModel.selectedAnnotationId != nil,
                        isTextSelected: {
                            guard let type = editModel.annotations.first(where: { $0.id == editModel.selectedAnnotationId })?.type else { return false }
                            return type == .text || type == .numberedText || type == .rectText
                        }(),
                        onUndo: editModel.undo,
                        onRedo: editModel.redo,
                        onPin: pinScreenshot,
                        onOCR: { exportAndClose(action: .ocr) },
                        onTranslate: { exportAndClose(action: .translate) },
                        onCancel: handleCancel,
                        onConfirm: { exportAndClose(action: .none) },
                        onGenerateDragURL: generateDragURL,
                        isEditingText: editModel.editingTextId != nil || editModel.editingCounterId != nil,
                        aiMarkerCount: editModel.annotations.filter({ $0.type == .aiMarker }).count,
                        onExportImage: { exportToAI(copyImage: true, copyCoords: false) },
                        onExportCoords: { exportToAI(copyImage: false, copyCoords: true) }
                    )
                    .frame(width: toolbarWidth)
                    .position(x: tbX, y: tbY)
                }
                
                // 7. 放大镜与取色器 (MagnifierView)
                if sessionState == .cropping || activeHandle != nil {
                    MagnifierView(
                        baseImage: capture.image,
                        hoverPoint: editModel.hoverPoint,
                        scaleFactor: capture.screen.backingScaleFactor,
                        selectedColor: sessionState == .cropping ? .blue : editModel.selectedColor,
                        onCopyColor: {
                            onCanceled()
                        }
                    )
                    .position(
                        x: min(max(editModel.hoverPoint.x + 80, 80), geometry.size.width - 80),
                        y: min(max(editModel.hoverPoint.y + 100, 100), geometry.size.height - 100)
                    )
                    .allowsHitTesting(false)
                }
                
                // 8. PSD-style 圆形画笔光标
                let isBrush = editModel.selectedTool == .pencil || editModel.selectedTool == .highlighter || editModel.selectedTool == .blur || editModel.selectedTool == .mosaic
                if editModel.isHoveringCanvas && isBrush {
                    let brushSize: CGFloat = {
                        if editModel.selectedTool == .pencil {
                            return editModel.selectedLineWidth
                        } else {
                            return editModel.selectedBrushSize
                        }
                    }()
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                        Circle()
                            .stroke(Color.black, lineWidth: 1.5)
                        Circle()
                            .stroke(Color.white, lineWidth: 0.8)
                    }
                    .frame(width: brushSize, height: brushSize)
                    .position(x: editModel.hoverPoint.x, y: editModel.hoverPoint.y)
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            self.availableWindows = WindowSnapper.getVisibleWindows(on: capture.screen)
            // 清除上一张截图的效果缓存
            BlurMosaicLiveView.clearEffectCache()
        }
        .onChange(of: editModel.selectedTool, perform: handleSelectedToolChanged)
        .edgesIgnoringSafeArea(.all)
        .onChange(of: editModel.selectedColor) { newColor in
            editModel.updateSelectedAnnotation(color: newColor)
        }
        .onChange(of: editModel.selectedFontSize) { newSize in
            editModel.updateSelectedAnnotation(fontSize: newSize)
        }
        .onChange(of: editModel.selectedLineWidth) { newSize in
            editModel.updateSelectedAnnotation(lineWidth: newSize)
        }
        .onChange(of: editModel.selectedBrushSize) { newSize in
            editModel.updateSelectedAnnotation(lineWidth: newSize)
        }
        .onChange(of: editModel.selectedTextStyle) { newStyle in
            editModel.updateSelectedAnnotation(style: newStyle)
        }
        .onChange(of: editModel.selectedAnnotationId) { newId in
            editModel.handleSelectionChange(to: newId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationDoubleTapped)) { notification in
            if let id = notification.object as? UUID {
                self.editModel.prepareForWrite()
                self.editModel.editingTextId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .counterDoubleTapped)) { notification in
            if let id = notification.object as? UUID {
                self.editModel.editingCounterId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitTextEdit)) { _ in
            if self.editModel.editingTextId != nil || self.editModel.editingCounterId != nil {
                self.editModel.commitAllEdits()
            }
        }
    }
    
    // MARK: - Interaction Handlers




    private func handleHover(_ point: CGPoint) {
        if sessionState == .editing {
            let isBrush = editModel.selectedTool == .pencil || editModel.selectedTool == .highlighter || editModel.selectedTool == .blur || editModel.selectedTool == .mosaic
            if isBrush && finalRect?.contains(point) == true {
                NSCursor.transparent.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else {
            // sessionState == .cropping
            // 找出鼠标所在的窗口并高亮
            if let win = availableWindows.first(where: { $0.rect.contains(point) }) {
                if hoverWindowRect != win.rect {
                    hoverWindowRect = win.rect
                    hoverWindowID = win.windowID
                }
            } else {
                if hoverWindowRect != nil { 
                    hoverWindowRect = nil
                    hoverWindowID = nil
                }
            }
            NSCursor.crosshair.set()
        }
    }
    
    private func handleDragStart(_ point: CGPoint, clickCount: Int) {
        if sessionState == .cropping {
            if startPoint == nil {
                startPoint = point
            }
            currentPoint = point
            return
        }
        // 预先 makeKey（文本工具需要键盘焦点）
        if editModel.selectedTool == .text || editModel.selectedTool == .numberedText {
            if let overlayWin = NSApp.windows.first(where: { $0 is CaptureOverlayWindow && $0.isVisible }) {
                overlayWin.makeKey()
            }
        }
        let outcome = editModel.handleDragStart(point, clickCount: clickCount, rectTextBounds: rectTextBounds, isPointInNumberedCircle: nil)
        if outcome == .hitEmpty {
            // 检查裁剪框 handle（OW 独有）
            if let rect = finalRect, let handle = AnnotationGeometry.hitTestHandle(point: point, in: rect, cornerMinHitZone: 5, edgeHitZone: 20) {
                activeHandle = handle
                initialRectBeforeDrag = rect
                dragStartPoint = point
                return
            }
            // 提交编辑态（OW 独有：只检查 editingTextId）
            editModel.selectedAnnotationId = nil
            if editModel.editingTextId != nil { editModel.commitTextEdit() }
            // 创建新标注
            if let newId = editModel.createNewAnnotation(at: point) {
                editModel.selectedAnnotationId = newId
            }
        }
    }

    private func handleDragChange(_ point: CGPoint) {
        if sessionState == .cropping {
            currentPoint = point
            return
        }
        // 先检查裁剪框 handle resize（OW 独有）
        if let handle = activeHandle, let initRect = initialRectBeforeDrag, let start = dragStartPoint {
            let dx = point.x - start.x
            let dy = point.y - start.y
            if handle == .calloutOrigin { return }
            var newRect = initRect
            switch handle {
            case .left:
                newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx)
                newRect.size.width = initRect.maxX - newRect.origin.x
            case .right:
                newRect.size.width = max(5, initRect.size.width + dx)
            case .top:
                newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy)
                newRect.size.height = initRect.maxY - newRect.origin.y
            case .bottom:
                newRect.size.height = max(5, initRect.size.height + dy)
            case .topLeft:
                newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx)
                newRect.size.width = initRect.maxX - newRect.origin.x
                newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy)
                newRect.size.height = initRect.maxY - newRect.origin.y
            case .topRight:
                newRect.size.width = max(5, initRect.size.width + dx)
                newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy)
                newRect.size.height = initRect.maxY - newRect.origin.y
            case .bottomLeft:
                newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx)
                newRect.size.width = initRect.maxX - newRect.origin.x
                newRect.size.height = max(5, initRect.size.height + dy)
            case .bottomRight:
                newRect.size.width = max(5, initRect.size.width + dx)
                newRect.size.height = max(5, initRect.size.height + dy)
            case .calloutOrigin:
                break
            }
            finalRect = newRect
            return
        }
        // 调用 ViewModel 处理标注拖拽
        editModel.handleDragChange(point) { finalRect }
    }

    private func handleDragEnd() {
        if sessionState == .cropping {
            // 裁剪分支（OW 独有，保留原逻辑）
            let isClick = startPoint != nil && currentPoint != nil && abs(startPoint!.x - currentPoint!.x) < 3 && abs(startPoint!.y - currentPoint!.y) < 3
            if isClick, let hoverRect = hoverWindowRect {
                finalRect = hoverRect
                sessionState = .editing
                if let overlayWin = NSApp.windows.first(where: { $0 is CaptureOverlayWindow && $0.isVisible }) {
                    overlayWin.makeKey()
                }
                return
            }
            if let rect = selectedRect, rect.width > 5 && rect.height > 5 {
                finalRect = rect
                sessionState = .editing
                if let overlayWin = NSApp.windows.first(where: { $0 is CaptureOverlayWindow && $0.isVisible }) {
                    overlayWin.makeKey()
                }
            } else {
                startPoint = nil
                currentPoint = nil
            }
            return
        }
        // 调用 ViewModel 处理标注拖拽结束
        editModel.handleDragEnd()
        // 裁剪框 handle 清理（OW 独有）
        if activeHandle != nil {
            activeHandle = nil
            initialRectBeforeDrag = nil
            dragStartPoint = nil
        }
    }
    
    // MARK: - Live Style Bindings

    private func offsetAnnotations(_ items: [AnnotationItem], by offset: CGPoint) -> [AnnotationItem] {
        return items.map { item in
            var newItem = item
            newItem.startPoint = CGPoint(x: item.startPoint.x - offset.x, y: item.startPoint.y - offset.y)
            newItem.endPoint = CGPoint(x: item.endPoint.x - offset.x, y: item.endPoint.y - offset.y)
            if let pts = item.points {
                newItem.points = pts.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
            }
            return newItem
        }
    }
    
    private func handleTextChanged(id: UUID, newText: String) {
        if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
            editModel.annotations[index].text = newText
        }
    }
    
    private func handleCounterChanged(id: UUID, newString: String) {
        if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
            editModel.annotations[index].customCounterString = newString
        }
    }

    private func handleSizeChanged(id: UUID, size: CGSize) {
        DispatchQueue.main.async {
            if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
                let item = editModel.annotations[index]
                if item.type == .numberedText || item.type == .rectText {
                    let offset = item.calloutOffset ?? (item.type == .rectText ? .zero : CGSize(width: 16.0, height: -45.0))
                    let originX = item.startPoint.x + offset.width
                    let originY = item.startPoint.y + offset.height
                    let endX = originX + size.width
                    let endY = originY + size.height
                    if item.endPoint.x != endX || item.endPoint.y != endY {
                        editModel.annotations[index].endPoint = CGPoint(x: endX, y: endY)
                    }
                } else {
                    let endX = item.startPoint.x + size.width
                    let endY = item.startPoint.y + size.height
                    if item.endPoint.x != endX || item.endPoint.y != endY {
                        editModel.annotations[index].endPoint = CGPoint(x: endX, y: endY)
                    }
                }
            }
        }
    }

    private func handleCancel() {
        onCanceled()
    }
    
    private func handleSelectedToolChanged(_ newTool: AnnotationToolType) {
        NotificationCenter.default.post(name: .selectedToolChanged, object: newTool)
        // 通过通知异步提交，避免 closure 直接捕获 OverlayRootView 实例方法导致闪崩
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .commitTextEdit, object: nil)
        }
    }
    // MARK: - Export
    @MainActor
    private func exportAndClose(action: PostCaptureAction = .none) {
        guard !hasCaptured, let rect = finalRect else { return }
        hasCaptured = true
        
        let scale = capture.screen.backingScaleFactor
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let cropped = capture.image.cropping(to: cropRect) else { return }
        var cleanCropped = cropped
        let shiftedAnnotations = offsetAnnotations(editModel.annotations, by: rect.origin)
        
        let isWindowSnap = (hoverWindowRect != nil && rect == hoverWindowRect)
        let windowCornerRadius: CGFloat = 14.0 * scale

        // 窗口吸附截图：优先使用 CGWindowListCreateImage 获取原生透明窗口（无阴影），
        // 再统一应用硬圆角遮罩，把圆角处半透明白/灰像素彻底清除为 RGBA(0,0,0,0)。
        if isWindowSnap {
            if let winID = hoverWindowID {
                let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
                if let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, winID, options) {
                    cleanCropped = windowImage
                }
            }
            cleanCropped = applyWindowCornerMask(to: cleanCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? cleanCropped
        }

        // 普通确认操作排除 AI 定位标记；但复制到 AI 时需要保留所有标注以便继续编辑
        let exportAnnotations = action == .copyToAI ? shiftedAnnotations : shiftedAnnotations.filter { $0.type != .aiMarker }

        if exportAnnotations.isEmpty {
            onCaptured(cleanCropped, cleanCropped, exportAnnotations, action)
            return
        }

        // 先同步把 blur/mosaic 画笔效果 burn 到原图上；ImageRenderer 不会等待 ImageEffectView 异步加载
        let displaySize = CGSize(width: rect.width, height: rect.height)
        let hasBlurMosaic = exportAnnotations.contains { $0.type == .blur || $0.type == .mosaic }
        let sourceImage = hasBlurMosaic ? (applyBrushEffects(to: cleanCropped, annotations: exportAnnotations, displaySize: displaySize) ?? cleanCropped) : cleanCropped

        let exportView = AnnotationCanvasLayer(
            image: sourceImage,
            displaySize: displaySize,
            annotations: exportAnnotations,
            currentAnnotation: nil,
            cornerRadius: 0,
            skipBlurMosaic: hasBlurMosaic
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale

        guard let rendered = renderer.cgImage,
              var finalCropped = ensurePremultipliedAlpha(for: rendered) else {
            AppLogger.ui.error("❌ [OverlayView] 标注合并渲染失败")
            onCanceled()
            return
        }

        // 窗口截图：对最终渲染结果再次应用硬圆角遮罩，确保圆角外无白色残留
        if isWindowSnap {
            finalCropped = applyWindowCornerMask(to: finalCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? finalCropped
        }

        onCaptured(finalCropped, cleanCropped, exportAnnotations, action)
    }
    
    @MainActor
    private func exportToAI(copyImage: Bool, copyCoords: Bool) {
        guard let rect = finalRect else { return }
        // 注意：不设置 hasCaptured = true，也不调用 onCaptured，让 overlay 保持打开
        // 用户可复制多项后再手动确认关闭
        
        let scale = capture.screen.backingScaleFactor
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        // 复制原图时必须使用截图时捕获的屏幕快照，不可重新捕获窗口（避免将当前 overlay 上的 AI 标记带入原图）
        guard let cropped = capture.image.cropping(to: cropRect) else { return }
        var cleanCropped = cropped
        let shiftedAnnotations = offsetAnnotations(editModel.annotations, by: rect.origin)
        let aiMarkers = shiftedAnnotations.filter { $0.type == .aiMarker }

        let isWindowSnap = (hoverWindowRect != nil && rect == hoverWindowRect)
        let windowCornerRadius: CGFloat = 14.0 * scale
        // 窗口截图：仅对原快照应用圆角遮罩，清除圆角处半透明白边；不重新捕获窗口内容
        if isWindowSnap {
            cleanCropped = applyWindowCornerMask(to: cleanCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? cleanCropped
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let pbItem = NSPasteboardItem()
        var textOutput = ""
        
        // 使用与保存文件一致的 CGImageDestination 生成 PNG，确保 alpha 通道不被丢弃
        var pngDataForClipboard: Data? = nil
        if copyImage {
            pngDataForClipboard = CaptureEngine.shared.pngData(from: cleanCropped)
            if let pngData = pngDataForClipboard {
                pbItem.setData(pngData, forType: .png)
            }
        }

        if copyCoords && !aiMarkers.isEmpty {
            textOutput = LanguageManager.shared.localizedString(forKey: "以下是在原图上圈出的目标元素坐标 [xmin, ymin, xmax, ymax]，请逐一根据坐标和关联的要求修改：") + "\n"
            for marker in aiMarkers.sorted(by: { ($0.counterValue ?? 0) < ($1.counterValue ?? 0) }) {
                let idStr = marker.displayCounterString
                let r = marker.rect
                let absStr = "[\(Int(r.minX * scale)), \(Int(r.minY * scale)), \(Int(r.maxX * scale)), \(Int(r.maxY * scale))]"
                textOutput += "\(idStr). \(absStr)\n"
            }
            pbItem.setString(textOutput, forType: .string)
        }
        
        if copyImage && copyCoords && !textOutput.isEmpty {
            let attrStr = NSMutableAttributedString()
            let attachment = NSTextAttachment()
            if let pngData = pngDataForClipboard {
                attachment.image = NSImage(data: pngData)
            } else {
                attachment.image = NSImage(cgImage: cleanCropped, size: NSSize(width: cleanCropped.width, height: cleanCropped.height))
            }
            attrStr.append(NSAttributedString(attachment: attachment))
            attrStr.append(NSAttributedString(string: "\n\n" + textOutput))
            if let rtfdData = attrStr.rtfd(from: NSRange(location: 0, length: attrStr.length), documentAttributes: [:]) {
                pbItem.setData(rtfdData, forType: .rtfd)
            }
        }
        
        pasteboard.writeObjects([pbItem])

        // Toast 反馈
        let toastKey: String
        if copyImage && copyCoords {
            toastKey = "已保存并复制原图和AI 定位坐标"
        } else if copyImage {
            toastKey = "已保存并复制原图"
        } else {
            toastKey = "已保存并复制 AI 定位坐标"
        }
        ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: toastKey))
        AppLogger.ui.debug("📋 [OverlayView] AI 导出完成: image=\(copyImage), coords=\(copyCoords)")
        
        // 复制后保存并切换为图像编辑窗口
        exportAndClose(action: .copyToAI)
    }
    @MainActor
    private func generateDragURL() -> URL? {
        guard !hasCaptured, let rect = finalRect else { return nil }
        
        let scale = capture.screen.backingScaleFactor
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let cropped = capture.image.cropping(to: cropRect) else { return nil }
        var cleanCropped = cropped
        let isWindowSnap = (hoverWindowRect != nil && rect == hoverWindowRect)
        let windowCornerRadius: CGFloat = 14.0 * scale

        // 窗口吸附截图：优先使用 CGWindowListCreateImage 获取原生透明窗口（无阴影），并应用硬圆角遮罩
        if isWindowSnap, let winID = hoverWindowID {
            let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
            if let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, winID, options) {
                cleanCropped = windowImage
            }
            cleanCropped = applyWindowCornerMask(to: cleanCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? cleanCropped
        }

        let shiftedAnnotations = offsetAnnotations(editModel.annotations, by: rect.origin)
        let displaySize = CGSize(width: rect.width, height: rect.height)
        let hasBlurMosaic = shiftedAnnotations.contains { $0.type == .blur || $0.type == .mosaic }
        let sourceImage = hasBlurMosaic ? (applyBrushEffects(to: cleanCropped, annotations: shiftedAnnotations, displaySize: displaySize) ?? cleanCropped) : cleanCropped

        let exportView = AnnotationCanvasLayer(
            image: sourceImage,
            displaySize: displaySize,
            annotations: shiftedAnnotations,
            currentAnnotation: nil,
            cornerRadius: 0,
            skipBlurMosaic: hasBlurMosaic
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale
        
        guard let rendered = renderer.cgImage,
              var finalCropped = ensurePremultipliedAlpha(for: rendered) else {
            return nil
        }

        // 窗口截图：对最终渲染结果应用硬圆角遮罩，确保拖拽出的文件圆角无白边
        if isWindowSnap {
            finalCropped = applyWindowCornerMask(to: finalCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? finalCropped
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, finalCropped, nil)
        return CGImageDestinationFinalize(destination) ? tempURL : nil
    }
    
    @MainActor
    private func pinScreenshot() {
        guard let rect = finalRect else { return }
        let scale = capture.screen.backingScaleFactor
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let cropped = capture.image.cropping(to: cropRect) else { return }
        var cleanCropped = cropped
        let isWindowSnap = (hoverWindowRect != nil && rect == hoverWindowRect)
        let windowCornerRadius: CGFloat = 14.0 * scale
        // 窗口吸附截图：优先使用 CGWindowListCreateImage 获取原生透明窗口（无阴影），并应用硬圆角遮罩
        if isWindowSnap, let winID = hoverWindowID {
            let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
            if let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, winID, options) {
                cleanCropped = windowImage
            }
            cleanCropped = applyWindowCornerMask(to: cleanCropped, cornerRadius: windowCornerRadius, inset: 1.0) ?? cleanCropped
        }

        let shiftedAnnotations = offsetAnnotations(editModel.annotations, by: rect.origin)
        
        if shiftedAnnotations.isEmpty {
            PinManager.shared.pin(image: cleanCropped)
            onCaptured(cleanCropped, cleanCropped, shiftedAnnotations, .none)
            return
        }
        
        let exportView = AnnotationCanvasLayer(
            image: cleanCropped,
            displaySize: CGSize(width: rect.width, height: rect.height),
            annotations: shiftedAnnotations,
            currentAnnotation: nil,
            cornerRadius: 0
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale
        
        if let rendered = renderer.cgImage,
           var cgImage = ensurePremultipliedAlpha(for: rendered) {
            // 窗口截图：对最终渲染结果应用硬圆角遮罩，确保贴图圆角无白边
            if isWindowSnap {
                cgImage = applyWindowCornerMask(to: cgImage, cornerRadius: windowCornerRadius, inset: 1.0) ?? cgImage
            }
            PinManager.shared.pin(image: cgImage)
            onCaptured(cgImage, cleanCropped, shiftedAnnotations, .none)
        }
    }
}

/// 统一的悬浮双层工具栏
struct UnifiedToolbarView: View {
    @Binding var selectedTool: AnnotationToolType
    @Binding var selectedColor: Color
    @Binding var selectedFontSize: CGFloat
    @Binding var selectedLineWidth: CGFloat
    @Binding var selectedBrushSize: CGFloat
    @Binding var selectedTextStyle: TextStyle
    
    var showTextStylePicker: Bool {
        selectedTool == .text || selectedTool == .numberedText || selectedTool == .rectText
    }
    
    let hasUndo: Bool
    let hasRedo: Bool
    let hasSelection: Bool
    var isTextSelected: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onGenerateDragURL: (@MainActor () -> URL?)?

    var isEditingText: Bool = false
    var aiMarkerCount: Int = 0
    var onExportImage: (() -> Void)? = nil
    var onExportCoords: (() -> Void)? = nil
    
    let colors: [Color] = TMDesign.Colors.toolbarPalette
    
    var body: some View {
        VStack(spacing: 0) {
            // 第一层：工具栏选择区与操作区
            HStack(spacing: 12) {
                // 1. Shapes 组
                HStack(spacing: 6) {
                    let shapeGroup: [AnnotationToolType] = [.rectangle, .filledRectangle, .ellipse, .line, .arrow]
                    ForEach(shapeGroup, id: \.self) { tool in
                        GroupButton(tool: tool, selected: $selectedTool)
                    }
                }
                
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 2)
                
                // 2. Text 组
                HStack(spacing: 6) {
                    GroupButton(tool: .text, selected: $selectedTool)
                    GroupButton(tool: .numberedText, selected: $selectedTool)
                    GroupButton(tool: .rectText, selected: $selectedTool)
                    GroupButton(tool: .counter, selected: $selectedTool)
                }
                
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 2)
                
                // 3. Effects 组
                HStack(spacing: 6) {
                    GroupButton(tool: .pencil, selected: $selectedTool)
                    GroupButton(tool: .highlighter, selected: $selectedTool)
                    GroupButton(tool: .blur, selected: $selectedTool)
                    GroupButton(tool: .mosaic, selected: $selectedTool)
                    GroupButton(tool: .spotlight, selected: $selectedTool)
                }
                
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 2)
                
                // 4. AI 组：给 AI 定位按钮 + 导出下拉菜单（视觉强关联）
                HStack(spacing: 6) {
                    GroupButton(tool: .aiMarker, selected: $selectedTool)
                    
                    // 导出下拉菜单与 AI 按钮紧邻，形成视觉关联
                    // 有标注时：紫渐变 + 计数角标；无标注时：灰色背景
                    ExportDropdownButton(
                        onExportImage: onExportImage,
                        onExportCoords: onExportCoords,
                        canExportCoords: aiMarkerCount > 0,
                        aiMarkerCount: aiMarkerCount
                    )
                }
                
                Spacer() // 将右侧内容推到右边

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 2)

                // 撤销和重做
                HStack(spacing: 8) {
                    IconButtonWithTooltip(
                        icon: "arrow.uturn.backward",
                        tooltipKey: "撤销 (Cmd+Z)",
                        action: onUndo,
                        isEnabled: hasUndo,
                        iconSize: 13,
                        foregroundColor: hasUndo ? .white : .primary.opacity(0.7),
                        backgroundColor: hasUndo ? Color.blue.opacity(0.85) : Color.gray.opacity(0.1)
                    )

                    IconButtonWithTooltip(
                        icon: "arrow.uturn.forward",
                        tooltipKey: "重做 (Cmd+Shift+Z)",
                        action: onRedo,
                        isEnabled: hasRedo,
                        iconSize: 13,
                        foregroundColor: hasRedo ? .white : .primary.opacity(0.7),
                        backgroundColor: hasRedo ? Color.blue.opacity(0.85) : Color.gray.opacity(0.1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // 第二层：属性调节面板
            VStack(spacing: 0) {
                Divider().padding(.vertical, 6)

                HStack(spacing: 16) {
                    // 颜色色板
                    HStack(spacing: 6) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.blue : Color.secondary.opacity(0.3), lineWidth: selectedColor == color ? 2.0 : 1.0)
                                )
                                .shadow(color: Color.black.opacity(selectedColor == color ? 0.3 : 0.1), radius: selectedColor == color ? 3 : 1)
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }

                    // 尺寸调节滑块 (Custom)
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        if showTextStylePicker || selectedTool == .counter {
                            TMThicknessSlider(value: $selectedFontSize, range: 12...128, step: 1)
                                .frame(width: 100)
                            Text("\(Int(selectedFontSize))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        } else if selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic {
                            TMThicknessSlider(value: $selectedBrushSize, range: 4...100, step: 1)
                                .frame(width: 100)
                            Text("\(Int(selectedBrushSize))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        } else {
                            TMThicknessSlider(value: $selectedLineWidth, range: 1...30, step: 1)
                                .frame(width: 100)
                            Text("\(Int(selectedLineWidth))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }

                    // 文字样式
                    Picker("", selection: $selectedTextStyle) {
                        ForEach(TextStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 90)
                    .opacity(showTextStylePicker ? 1 : 0)
                    .allowsHitTesting(showTextStylePicker)

                    Spacer()

                    // 5. 进阶操作组 (Pin, Translate, OCR, Delete) 以及导出菜单
                    HStack(spacing: 8) {

                        // Extra tools - 蓝色图标默认态，hover 反转为白图标+蓝背景，明确可交互
                        IconButtonWithTooltip(
                            icon: "text.viewfinder",
                            tooltipKey: "提取文字",
                            action: onOCR
                        )

                        IconButtonWithTooltip(
                            icon: sfSymbol("translate", fallback: "globe"),
                            tooltipKey: "翻译文字",
                            action: onTranslate
                        )

                        IconButtonWithTooltip(
                            icon: "pin",
                            tooltipKey: "钉住到屏幕",
                            action: onPin
                        )

                        Text("|").foregroundColor(.gray.opacity(0.4)).padding(.horizontal, 2)

                        // Cancel
                        CircleButtonWithTooltip(
                            icon: "xmark",
                            tooltipKey: "取消 (Esc)",
                            action: onCancel,
                            backgroundColor: Color.red.opacity(0.8)
                        )

                        // Confirm
                        CircleButtonWithTooltip(
                            icon: "checkmark",
                            tooltipKey: "完成并保存",
                            action: onConfirm,
                            backgroundColor: Color.green
                        )

                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .onChange(of: selectedTool) { newTool in
            if newTool == .numberedText || newTool == .rectText {
                selectedTextStyle = .roundedBoxed
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 20)
        )
    }
}

struct GroupButton: View {
    let tool: AnnotationToolType
    @Binding var selected: AnnotationToolType
    @State private var isHovered = false
    
    var isSelected: Bool {
        selected == tool
    }
    
    var iconName: String {
        switch tool {
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "a.square"
        case .numberedText: return "text.badge.plus"
        case .counter: return "1.circle.fill"
        case .rectText: return sfSymbol("bubble.and.pencil", fallback: "text.bubble")
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .blur: return "drop.fill"
        case .mosaic: return "checkerboard.rectangle"
        case .spotlight: return "viewfinder.circle.fill"
        case .aiMarker: return "location.fill.viewfinder"
        }
    }
    
    var toolName: String {
        switch tool {
        case .rectangle: return "矩形"
        case .filledRectangle: return "实心矩形"
        case .ellipse: return "圆形"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .text: return "文字"
        case .numberedText: return "序号文字"
        case .rectText: return "矩形框文本"
        case .counter: return "计数器"
        case .pencil: return "画笔"
        case .highlighter: return "荧光笔"
        case .blur: return "模糊"
        case .mosaic: return "马赛克"
        case .spotlight: return "聚焦"
        case .aiMarker: return "给 AI 定位"
        }
    }
    
    private var aiThemed: Bool {
        tool == .aiMarker
    }
    
    private var btnForeground: Color {
        if isSelected { return .white }
        if aiThemed { return isHovered ? .white : TMDesign.Colors.purple.opacity(0.85) }
        return isHovered ? .primary : .secondary
    }

    private var btnBackground: Color {
        if isSelected {
            return aiThemed ? TMDesign.Colors.purple.opacity(0.7) : TMDesign.Colors.blue
        }
        if aiThemed { return isHovered ? TMDesign.Colors.purple.opacity(0.7) : TMDesign.Colors.purple.opacity(0.1) }
        return isHovered ? Color.gray.opacity(0.15) : Color.clear
    }
    
    var body: some View {
        Button(action: {
            selected = tool
        }) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(btnForeground)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(btnBackground)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .overlay(
            Group {
                if isHovered {
                    Text(LanguageManager.shared.localizedString(forKey: toolName))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .fixedSize()
                        // 悬浮在按钮正上方
                        .offset(y: -32)
                        // 避免阻挡鼠标事件
                        .allowsHitTesting(false)
                }
            }
        )
        // 保留原有的 help 作为无障碍和后备支持
        .help(LanguageManager.shared.localizedString(forKey: toolName))
    }
}

/// 带自定义 hover tooltip 的图标按钮（解决 LSUIElement 应用系统 .help() tooltip 不显示的问题）
/// 默认态使用蓝色图标 + 极浅背景，hover 态反转为白图标 + 蓝色背景，明确传达可交互性
struct IconButtonWithTooltip: View {
    let icon: String
    let tooltipKey: String
    let action: () -> Void
    var isEnabled: Bool = true
    var iconSize: CGFloat = 15
    var buttonSize: CGFloat = 32
    
    // 允许外部覆盖颜色（如 Delete 按钮需要红色）
    var foregroundColor: Color? = nil
    var backgroundColor: Color? = nil
    var hoverForegroundColor: Color? = nil
    var hoverBackgroundColor: Color? = nil
    
    // 颜色配置：默认态 vs Hover 态
    private var defaultFg: Color { foregroundColor ?? TMDesign.Colors.blue }
    private var defaultBg: Color { backgroundColor ?? TMDesign.Colors.blue.opacity(0.1) }
    private var hoverFg: Color { hoverForegroundColor ?? .white }
    private var hoverBg: Color { hoverBackgroundColor ?? TMDesign.Colors.blue.opacity(0.85) }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(isEnabled ? (isHovered ? hoverFg : defaultFg) : Color.gray.opacity(0.5))
                .frame(width: buttonSize, height: buttonSize)
                .background(isEnabled ? (isHovered ? hoverBg : defaultBg) : Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .overlay(
            Group {
                if isHovered {
                    Text(LanguageManager.shared.localizedString(forKey: tooltipKey))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .fixedSize()
                        .offset(y: -28)
                        .allowsHitTesting(false)
                }
            }
        )
    }
}

struct CircleButtonWithTooltip: View {
    let icon: String
    let tooltipKey: String
    let action: () -> Void
    var foregroundColor: Color = .white
    var backgroundColor: Color = Color.red.opacity(0.8)
    var iconSize: CGFloat = 12
    var buttonSize: CGFloat = 32
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(foregroundColor)
                .padding(6)
                .background(backgroundColor)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .overlay(
            Group {
                if isHovered {
                    Text(LanguageManager.shared.localizedString(forKey: tooltipKey))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .fixedSize()
                        .offset(y: -28)
                        .allowsHitTesting(false)
                }
            }
        )
    }
}

/// 第三栏 AI 操作按钮（带文本标签 + 自定义 tooltip）
struct AIActionButtonWithTooltip: View {
    let icon: String
    let tooltipKey: String
    let action: () -> Void
    var backgroundColor: Color = Color.blue.opacity(0.8)
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(LanguageManager.shared.localizedString(forKey: tooltipKey))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(backgroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
        .overlay(
            Group {
                if isHovered {
                    Text(LanguageManager.shared.localizedString(forKey: tooltipKey))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .fixedSize()
                        .offset(y: -28)
                        .allowsHitTesting(false)
                }
            }
        )
    }
}

/// 导出下拉菜单按钮（AI 语义：替代第三栏，合并复制原图/复制坐标）
/// 点击后按钮进入选中态，上方弹出常驻气泡给出两个选项
struct ExportDropdownButton: View {
    let onExportImage: (() -> Void)?
    let onExportCoords: (() -> Void)?
    var canExportCoords: Bool = false
    var aiMarkerCount: Int = 0

    @State private var isShowingPopover = false

    var body: some View {
        Button(action: {
            isShowingPopover.toggle()
        }) {
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    // 有 AI 标记时图标为白色（点亮），无标记时保持可见但为灰色，避免看起来像禁用
                    .foregroundColor(aiMarkerCount > 0 ? .white : Color.gray.opacity(0.9))

                Image(systemName: "chevron.down")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundColor(aiMarkerCount > 0 ? Color.white.opacity(0.85) : Color.gray.opacity(0.7))
                    .offset(x: 9, y: 9)

                // 计数角标：使用与 AI marker 一致的紫色
                if aiMarkerCount > 0 {
                    Text("\(aiMarkerCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(TMDesign.Colors.purple.opacity(0.9))
                        .clipShape(Circle())
                        .offset(x: 12, y: -12)
                }
            }
            .frame(width: 32, height: 32)
            // 有 AI 标记时按钮为紫色主题（可导出状态）；无标记时灰色背景，仍可点击打开提示
            .background(aiMarkerCount > 0
                ? TMDesign.Colors.purple.opacity(isShowingPopover ? 0.85 : 0.7)
                : Color.gray.opacity(isShowingPopover ? 0.45 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    onExportImage?()
                    isShowingPopover = false
                }) {
                    Label(LanguageManager.shared.localizedString(forKey: "复制原图"), systemImage: "photo.on.rectangle")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                    .padding(.horizontal, 4)

                Button(action: {
                    if canExportCoords {
                        onExportCoords?()
                        isShowingPopover = false
                    } else {
                        ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "请先添加 AI 定位标记"))
                    }
                }) {
                    Label(LanguageManager.shared.localizedString(forKey: "复制坐标"), systemImage: "doc.on.doc")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)
        }
    }
}

struct TMThicknessSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>
    var step: CGFloat = 1
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeW = max(1, w - 14) // reserve space for thumb
            let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbX = 7 + CGFloat(ratio) * safeW
            
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                
                // Active Track
                Capsule()
                    .fill(Color.blue)
                    .frame(width: max(0, thumbX), height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .frame(width: 14, height: 14)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let percent = (drag.location.x - 7) / safeW
                        let newValue = range.lowerBound + percent * (range.upperBound - range.lowerBound)
                        let stepped = round(newValue / step) * step
                        value = max(range.lowerBound, min(range.upperBound, stepped))
                    }
            )
        }
        .frame(height: 24)
    }
}
