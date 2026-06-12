import Cocoa
import SwiftUI
import Translation

public enum PostCaptureAction: String {
    case none
    case ocr
    case translate
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
    let onDragStart: (CGPoint) -> Void
    let onDragChange: (CGPoint) -> Void
    let onDragEnd: () -> Void
    let onCancel: () -> Void
    var onHover: ((CGPoint) -> Void)? = nil
    var onHoverExited: (() -> Void)? = nil
    var activeTool: AnnotationToolType = .rectangle
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
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
        view.updateCursor()
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
        if nsView.activeTool != activeTool {
            nsView.activeTool = activeTool
            nsView.updateCursor()
        }
    }
}

class TrackingNSView: NSView {
    var onDown: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onUp: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHover: ((CGPoint) -> Void)?
    var onHoverExited: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDelete: (() -> Void)?
    var activeTool: AnnotationToolType = .rectangle

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
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)
    }
    
    override func mouseEntered(with event: NSEvent) {
        updateCursor()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
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
        updateCursor()
        onHover?(point)
        onDown?(point)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor()
        onHover?(point)
        onDrag?(point)
    }
    
    override func mouseUp(with event: NSEvent) {
        updateCursor()
        onUp?()
    }
    
    func updateCursor() {
        let isBrush = activeTool == .pencil || activeTool == .highlighter || activeTool == .blur || activeTool == .mosaic
        if isBrush {
            NSCursor.transparent.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

/// 悬浮遮罩管理器，控制所有屏幕的截图遮罩窗口
public class OverlayManager {
    public static let shared = OverlayManager()
    private var windows: [NSWindow] = []
    
    private init() {}
    
    /// 唤起全屏截图遮罩
    private var escMonitor: Any?
    private var escGlobalMonitor: Any?
    public func showOverlay(captures: [ScreenCapture], onCaptured: @escaping (CGImage, CGImage?, [AnnotationItem]?, NSScreen, PostCaptureAction) -> Void, canceled: @escaping () -> Void) {
        print("ℹ️ [OverlayManager] 开始唤起 \(captures.count) 个遮罩窗口...")
        closeAll() // 防御性清理
        
        // 注册全局 ESC 键监听
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC 键
                print("ℹ️ [OverlayManager] 监听到全局 ESC 键，取消截图")
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
                print("ℹ️ [OverlayManager] (Global) 监听到 ESC 键，取消截图")
                DispatchQueue.main.async {
                    canceled()
                    self?.closeAll()
                }
            }
        }
        
        for capture in captures {
            let screen = capture.screen
            let screenFrame = screen.frame
            
            print("ℹ️ [OverlayManager] 屏幕信息 - frame: \(screenFrame), visibleFrame: \(screen.visibleFrame), backingScaleFactor: \(screen.backingScaleFactor)")
            
            let rootView = OverlayRootView(capture: capture, onCaptured: { image, cleanImage, annotations, action in
                print("ℹ️ [OverlayManager] 遮罩层触发 onCaptured，开始执行回调...")
                onCaptured(image, cleanImage, annotations, screen, action)
                self.closeAll()
            }, onCanceled: {
                print("ℹ️ [OverlayManager] 遮罩层触发 onCanceled...")
                canceled()
                self.closeAll()
            })
            
            let hostingView = TrackingHostingView(rootView: rootView.applyAppLanguage())
            hostingView.frame = NSRect(origin: .zero, size: screenFrame.size)
            
            let window = CaptureOverlayWindow(
                contentRect: screenFrame,
                styleMask: [.borderless], // 移除 .nonactivatingPanel 以强制获取焦点
                backing: .buffered,
                defer: false,
                screen: screen
            )
            
            // 先配置窗口属性
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.5) // 临时用半透明黑测试可见性
            window.isOpaque = false
            window.hasShadow = false
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
            
            print("ℹ️ [OverlayManager] 窗口属性 - frame: \(window.frame), contentView.bounds: \(window.contentView?.bounds ?? .zero), hostingView.frame: \(hostingView.frame)")
            
            // 激活应用并显示窗口
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            // 验证窗口状态
            print("ℹ️ [OverlayManager] 窗口状态 - isVisible: \(window.isVisible), isKeyWindow: \(window.isKeyWindow), isMainWindow: \(window.isMainWindow), level: \(window.level.rawValue), windowNumber: \(window.windowNumber)")
            print("ℹ️ [OverlayManager] contentView - frame: \(window.contentView?.frame ?? .zero), isHidden: \(window.contentView?.isHidden ?? true)")
            
            windows.append(window)
        }
        
        print("ℹ️ [OverlayManager] 窗口创建完毕，当前持有窗口数: \(windows.count)")
    }
    
    /// 关闭所有遮罩窗口
    public func closeAll() {
        print("ℹ️ [OverlayManager] 执行 closeAll，当前窗口数: \(self.windows.count)")
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
        print("✅ [OverlayManager] 遮罩窗口已全部销毁")
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
    
    @State private var sessionState: CaptureSessionState = .cropping
    
    // 裁剪框状态
    @State private var startPoint: CGPoint? = nil
    @State private var currentPoint: CGPoint? = nil
    @State private var finalRect: CGRect? = nil
    
    // 裁剪框调整状态
    @State private var activeHandle: DragHandle? = nil
    @State private var initialRectBeforeDrag: CGRect? = nil
    @State private var dragStartPoint: CGPoint? = nil
    
    // 标注相关状态
    @State private var annotations: [AnnotationItem] = []
    @State private var currentAnnotation: AnnotationItem? = nil
    @State private var editingTextId: UUID? = nil
    @State private var selectedTool: AnnotationToolType = .rectangle
    @State private var selectedColor: Color = .red
    @State private var selectedSize: CGFloat = 24.0
    @State private var selectedTextStyle: TextStyle = .standard
    
    // 标注选中与调整状态
    @State private var selectedAnnotationId: UUID? = nil
    @State private var annotationActiveHandle: DragHandle? = nil
    @State private var annotationInitialItem: AnnotationItem? = nil
    @State private var annotationDragStartPoint: CGPoint? = nil
    
    // 撤销/重做栈
    @State private var undoStack: [[AnnotationItem]] = []
    @State private var redoStack: [[AnnotationItem]] = []
    
    @State private var hoverPoint: CGPoint = .zero
    @State private var isHoveringCanvas: Bool = false
    
    private func prepareForWrite() {
        if undoStack.isEmpty || undoStack.last != annotations {
            undoStack.append(annotations)
            redoStack.removeAll()
        }
    }
    
    private func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
    }
    
    private func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
    }
    
    @State private var hasCaptured: Bool = false
    
    @State private var dragStartPos: CGPoint? = nil
    @State private var lastDragPoint: CGPoint? = nil
    
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
                    .onTapGesture(perform: handleTextCommit)
                
                // 2. 标注层：仅在选区范围内可见或整个屏幕都可见？（整个屏幕更自由，但保存时仅裁剪选区）
                AnnotationCanvasLayer(
                    image: capture.image,
                    displaySize: CGSize(width: geometry.size.width, height: geometry.size.height),
                    annotations: annotations,
                    currentAnnotation: currentAnnotation,
                    selectedAnnotationId: selectedAnnotationId,
                    editingTextId: editingTextId,
                    onTextChanged: handleTextChanged,
                    onTextCommit: handleTextCommit,
                    onSizeChanged: handleSizeChanged,
                    clipRect: finalRect
                )
                
                // 3. 中层：半透明变暗背景（挖空选区）
                InverseRectangle(subRect: selectedRect)
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false) // 让事件穿透
                
                // 4. 选区边框与尺寸标签
                if let rect = selectedRect {
                    // 蓝色精致边框
                    Rectangle()
                        .stroke(sessionState == .cropping ? Color.blue : Color.white.opacity(0.5), lineWidth: 1.5)
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
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .position(handlePosition(for: handle, rect: rect))
                                .allowsHitTesting(false)
                        }
                    }
                }
                // 5. 事件接收层
                
                // 隐藏的撤销重做按钮
                Button("") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .frame(width: 0, height: 0)
                Button("") { redo() }
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
                            annotations.removeAll()
                            activeHandle = nil
                        } else {
                            onCanceled()
                        }
                    },
                    onHover: { pt in
                        if sessionState == .editing {
                            if let rect = finalRect, rect.contains(pt) {
                                hoverPoint = pt
                                isHoveringCanvas = true
                                handleHover(pt)
                            } else {
                                isHoveringCanvas = false
                                NSCursor.arrow.set()
                            }
                        } else {
                            hoverPoint = pt
                            isHoveringCanvas = true
                            handleHover(pt)
                        }
                    },
                    onHoverExited: {
                        isHoveringCanvas = false
                    },
                    activeTool: selectedTool,
                    onUndo: undo,
                    onRedo: redo,
                    onDelete: handleDelete
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(editingTextId == nil)
                
                // 6. 悬浮工具栏 (仅在编辑状态下显示)
                if sessionState == .editing, let rect = finalRect {
                    let toolbarWidth: CGFloat = 650.0 // 估计的紧凑工具栏宽度
                    let toolbarHeight: CGFloat = 90.0
                    let padding: CGFloat = 12.0
                    
                    let tbX = max(toolbarWidth / 2 + padding, min(geometry.size.width - toolbarWidth / 2 - padding, rect.midX))
                    let spaceBelow = geometry.size.height - rect.maxY
                    let tbY: CGFloat = (spaceBelow < toolbarHeight + padding * 2) ? max(toolbarHeight / 2 + padding, rect.minY - padding - toolbarHeight / 2) : rect.maxY + padding + toolbarHeight / 2
                    
                    UnifiedToolbarView(
                        selectedTool: $selectedTool,
                        selectedColor: $selectedColor,
                        selectedSize: $selectedSize,
                        selectedTextStyle: $selectedTextStyle,
                        hasUndo: !undoStack.isEmpty,
                        hasRedo: !redoStack.isEmpty,
                        hasSelection: selectedAnnotationId != nil,
                        onUndo: undo,
                        onRedo: redo,
                        onDelete: handleDelete,
                        onPin: pinScreenshot,
                        onOCR: { exportAndClose(action: .ocr) },
                        onTranslate: { exportAndClose(action: .translate) },
                        onCancel: handleCancel,
                        onConfirm: { exportAndClose(action: .none) }
                    )
                    .fixedSize()
                    .position(x: tbX, y: tbY)
                }
                
                // 7. PSD-style 圆形画笔光标
                if isHoveringCanvas && (selectedTool == .pencil || selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic) {
                    let brushSize: CGFloat = {
                        let lw = max(1.0, selectedSize / 4.0)
                        if selectedTool == .pencil {
                            return lw
                        } else {
                            return max(20.0, lw * 2.0)
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
                    .position(x: hoverPoint.x, y: hoverPoint.y)
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: selectedTool, perform: handleSelectedToolChanged)
        .edgesIgnoringSafeArea(.all)
        .onChange(of: selectedColor) { newColor in
            updateSelectedAnnotation(color: newColor)
        }
        .onChange(of: selectedSize) { newSize in
            updateSelectedAnnotation(size: newSize)
        }
        .onChange(of: selectedTextStyle) { newStyle in
            updateSelectedAnnotation(style: newStyle)
        }
        .onChange(of: selectedAnnotationId) { newId in
            handleSelectionChange(to: newId)
        }
    }
    
    // MARK: - Interaction Handlers
    

    
    private let handleHitZone: CGFloat = 20.0
    
    private func hitTestHandle(point: CGPoint, rect: CGRect) -> DragHandle? {
        let hitRect = rect.insetBy(dx: -handleHitZone, dy: -handleHitZone)
        guard hitRect.contains(point) else { return nil }
        
        let p = point
        let isNear = { (val: CGFloat, target: CGFloat) in abs(val - target) <= self.handleHitZone }
        
        if isNear(p.x, rect.minX) && isNear(p.y, rect.minY) { return .topLeft }
        if isNear(p.x, rect.maxX) && isNear(p.y, rect.minY) { return .topRight }
        if isNear(p.x, rect.minX) && isNear(p.y, rect.maxY) { return .bottomLeft }
        if isNear(p.x, rect.maxX) && isNear(p.y, rect.maxY) { return .bottomRight }
        if isNear(p.x, rect.minX) { return .left }
        if isNear(p.x, rect.maxX) { return .right }
        if isNear(p.y, rect.minY) { return .top }
        if isNear(p.y, rect.maxY) { return .bottom }
        return nil
    }
    
    private func handleHover(_ point: CGPoint) {
        if sessionState == .editing {
            // 1. Check annotation handles if selected
            if let selectedId = selectedAnnotationId,
               let index = annotations.firstIndex(where: { $0.id == selectedId }) {
                let itemRect = annotations[index].rect
                if let handle = hitTestHandle(point: point, rect: itemRect) {
                    switch handle {
                    case .left, .right: NSCursor.resizeLeftRight.set()
                    case .top, .bottom: NSCursor.resizeUpDown.set()
                    case .topLeft, .bottomRight: NSCursor.crosshair.set() // Alternatively, implement diagonal cursors later
                    case .topRight, .bottomLeft: NSCursor.crosshair.set()
                    }
                    return
                } else if itemRect.contains(point) {
                    NSCursor.openHand.set()
                    return
                }
            }
            
            // 2. Check other annotations for openHand
            if annotations.reversed().contains(where: { $0.rect.contains(point) }) {
                NSCursor.openHand.set()
                return
            }
            
            // 3. Check finalRect handles
            if let rect = finalRect, let handle = hitTestHandle(point: point, rect: rect) {
                switch handle {
                case .left, .right: NSCursor.resizeLeftRight.set()
                case .top, .bottom: NSCursor.resizeUpDown.set()
                case .topLeft, .bottomRight: NSCursor.crosshair.set()
                case .topRight, .bottomLeft: NSCursor.crosshair.set()
                }
                return
            }
            
            // 4. Outside finalRect area should be arrow
            if let rect = finalRect, !rect.contains(point) {
                NSCursor.arrow.set()
                return
            }
            
            let isBrush = selectedTool == .pencil || selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic
            if isBrush {
                NSCursor.transparent.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }
    
    private func handleDragStart(_ point: CGPoint) {
        dragStartPos = point
        lastDragPoint = point
        if sessionState == .cropping {
            if startPoint == nil {
                startPoint = point
            }
            currentPoint = point
        } else {
            // 1. Check if clicking on selected annotation's handles or body
            if let selectedId = selectedAnnotationId,
               let index = annotations.firstIndex(where: { $0.id == selectedId }) {
                let itemRect = annotations[index].rect
                if let handle = hitTestHandle(point: point, rect: itemRect) {
                    prepareForWrite()
                    annotationActiveHandle = handle
                    annotationInitialItem = annotations[index]
                    annotationDragStartPoint = point
                    return
                } else if itemRect.contains(point) {
                    prepareForWrite()
                    annotationActiveHandle = nil // means moving
                    annotationInitialItem = annotations[index]
                    annotationDragStartPoint = point
                    return
                }
            }
            
            // 2. Check if clicking on another annotation
            if let hitAnnotation = annotations.reversed().first(where: { $0.rect.contains(point) }) {
                prepareForWrite()
                selectedAnnotationId = hitAnnotation.id
                annotationActiveHandle = nil
                annotationInitialItem = hitAnnotation
                annotationDragStartPoint = point
                return
            }
            
            // 3. Check crop box handles (Lowest Priority)
            if let rect = finalRect, let handle = hitTestHandle(point: point, rect: rect) {
                // 开始调整裁剪框
                activeHandle = handle
                initialRectBeforeDrag = rect
                dragStartPoint = point
                return
            }
            
            // 4. Clear selection and draw new
            selectedAnnotationId = nil
            
            if editingTextId != nil {
                editingTextId = nil
            }
            
            if selectedTool == .text || selectedTool == .numberedText {
                prepareForWrite()
                if let overlayWin = NSApp.windows.first(where: { $0 is CaptureOverlayWindow && $0.isVisible }) {
                    overlayWin.makeKey()
                }
                var cValue: Int? = nil
                if selectedTool == .numberedText {
                    let existingCount = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count
                    cValue = existingCount + 1
                }
                let textItem = AnnotationItem(
                    type: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: selectedColor,
                    lineWidth: 2.0,
                    text: "",
                    fontStyle: selectedTextStyle,
                    fontSize: selectedSize,
                    counterValue: cValue
                )
                annotations.append(textItem)
                editingTextId = textItem.id
            } else {
                if currentAnnotation == nil {
                    prepareForWrite()
                    var cValue: Int? = nil
                    if selectedTool == .counter || selectedTool == .numberedText {
                        let existingCount = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count
                        cValue = existingCount + 1
                    }
                    
                    var newAnnotation = AnnotationItem(
                        type: selectedTool,
                        startPoint: point,
                        endPoint: point, // Fix for counter to appear immediately
                        color: selectedColor,
                        lineWidth: max(1.0, selectedSize / 4.0),
                        fontStyle: selectedTextStyle,
                        fontSize: selectedSize,
                        counterValue: cValue
                    )
                    
                    if newAnnotation.isFreehandTool {
                        newAnnotation.points = [point]
                    }
                    
                    currentAnnotation = newAnnotation
                }
                
                if currentAnnotation?.isFreehandTool == true {
                    currentAnnotation?.points?.append(point)
                }
                currentAnnotation?.endPoint = point
            }
        }
    }
    
    private func handleDragChange(_ point: CGPoint) {
        lastDragPoint = point
        if sessionState == .cropping {
            currentPoint = point
        } else {
            // Editing State
            
            // Check if moving/resizing an annotation
            if let selectedId = selectedAnnotationId,
               let index = annotations.firstIndex(where: { $0.id == selectedId }),
               let initialItem = annotationInitialItem,
               let start = annotationDragStartPoint {
                
                let dx = point.x - start.x
                let dy = point.y - start.y
                var updatedItem = initialItem
                
                if let handle = annotationActiveHandle {
                    // Resize
                    let initRect = initialItem.rect
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
                    }
                    
                    updatedItem.resize(to: newRect, from: initRect)
                } else {
                    // Move
                    updatedItem.move(by: CGSize(width: dx, height: dy))
                }
                
                annotations[index] = updatedItem
                return
            }
            
            if let handle = activeHandle, let initRect = initialRectBeforeDrag, let start = dragStartPoint {
                let dx = point.x - start.x
                let dy = point.y - start.y
                
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
                }
                finalRect = newRect
                return
            }
            
            if selectedTool != .text {
                if currentAnnotation?.isFreehandTool == true {
                    currentAnnotation?.points?.append(point)
                    // Optionally update endPoint for bounding box calculations
                    currentAnnotation?.endPoint = point
                } else {
                    currentAnnotation?.endPoint = point
                }
            }
        }
    }
    
    private func handleDragEnd() {
        if sessionState == .cropping {
            if let rect = selectedRect, rect.width > 5 && rect.height > 5 {
                // 进入编辑模式
                finalRect = rect
                sessionState = .editing
                if let overlayWin = NSApp.windows.first(where: { $0 is CaptureOverlayWindow && $0.isVisible }) {
                    overlayWin.makeKey()
                }
            } else {
                startPoint = nil
                currentPoint = nil
            }
        } else {
            // Editing State
            
            // 检测单击进入编辑（在已选中的文本上点击且无大位移）
            if let startPos = dragStartPos,
               let lastPos = lastDragPoint,
               let selectedId = selectedAnnotationId,
               let index = annotations.firstIndex(where: { $0.id == selectedId }) {
                let dx = abs(lastPos.x - startPos.x)
                let dy = abs(lastPos.y - startPos.y)
                let isText = annotations[index].type == .text || annotations[index].type == .numberedText
                if isText && dx < 5 && dy < 5 {
                    prepareForWrite()
                    editingTextId = selectedId
                }
            }
            dragStartPos = nil
            lastDragPoint = nil
            
            // Check if we just finished moving/resizing an annotation
            if annotationInitialItem != nil {
                let changed = (undoStack.last != annotations)
                annotationInitialItem = nil
                annotationDragStartPoint = nil
                annotationActiveHandle = nil
                if !changed {
                    if !undoStack.isEmpty {
                        _ = undoStack.removeLast()
                    }
                }
                return
            }
            
            if activeHandle != nil {
                activeHandle = nil
                initialRectBeforeDrag = nil
                dragStartPoint = nil
                return
            }
            
            if selectedTool != .text {
                if let final = currentAnnotation {
                    var shouldSave = false
                    if final.isFreehandTool {
                        if let points = final.points, points.count > 3 {
                            annotations.append(final)
                            shouldSave = true
                        }
                    } else {
                        let dx = abs(final.startPoint.x - final.endPoint.x)
                        let dy = abs(final.startPoint.y - final.endPoint.y)
                        if final.type == .counter || dx > 5 || dy > 5 {
                            annotations.append(final)
                            shouldSave = true
                        }
                    }
                    if !shouldSave {
                        if !undoStack.isEmpty {
                            _ = undoStack.removeLast()
                        }
                    }
                }
                currentAnnotation = nil
            }
        }
    }
    
    // MARK: - Live Style Bindings
    private func updateSelectedAnnotation(color: Color? = nil, size: CGFloat? = nil, style: TextStyle? = nil) {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }
        
        var item = annotations[index]
        var changed = false
        
        if let newColor = color, item.color != newColor {
            item.color = newColor
            changed = true
        }
        
        if let newSize = size {
            if item.type == .text || item.type == .numberedText || item.type == .counter {
                if item.fontSize != newSize {
                    item.fontSize = newSize
                    changed = true
                }
            } else {
                let mappedWidth = max(1.0, newSize / 4.0)
                if item.lineWidth != mappedWidth {
                    item.lineWidth = mappedWidth
                    changed = true
                }
            }
        }
        
        if let newStyle = style, (item.type == .text || item.type == .numberedText) {
            if item.fontStyle != newStyle {
                item.fontStyle = newStyle
                changed = true
            }
        }
        
        if changed {
            prepareForWrite()
            annotations[index] = item
        }
    }
    
    private func handleSelectionChange(to newId: UUID?) {
        guard let id = newId, let item = annotations.firstIndex(where: { $0.id == id }).map({ annotations[$0] }) else { return }
        
        selectedColor = item.color
        if item.type == .text || item.type == .numberedText || item.type == .counter {
            selectedSize = item.fontSize ?? 24.0
        } else {
            selectedSize = item.lineWidth * 4.0
        }
        if let style = item.fontStyle {
            selectedTextStyle = style
        }
    }
    
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
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index].text = newText
        }
    }
    
    private func handleTextCommit() {
        if let index = annotations.firstIndex(where: { $0.id == editingTextId }) {
            let text = annotations[index].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                prepareForWrite()
                annotations.remove(at: index)
            }
        }
        editingTextId = nil
    }

    private func handleSizeChanged(id: UUID, size: CGSize) {
        DispatchQueue.main.async {
            if let index = annotations.firstIndex(where: { $0.id == id }) {
                let item = annotations[index]
                let endX = item.startPoint.x + size.width
                let endY = item.startPoint.y + size.height
                if item.endPoint.x != endX || item.endPoint.y != endY {
                    annotations[index].endPoint = CGPoint(x: endX, y: endY)
                }
            }
        }
    }

    private func handleDelete() {
        if let selectedId = selectedAnnotationId {
            prepareForWrite()
            if let index = annotations.firstIndex(where: { $0.id == selectedId }) {
                let deletedItem = annotations[index]
                annotations.remove(at: index)
                
                // 序号顺延逻辑 (Phase 2)
                if deletedItem.type == .counter || deletedItem.type == .numberedText,
                   let deletedValue = deletedItem.counterValue {
                    for i in 0..<annotations.count {
                        if (annotations[i].type == .counter || annotations[i].type == .numberedText),
                           let val = annotations[i].counterValue, val > deletedValue {
                            annotations[i].counterValue = val - 1
                        }
                    }
                }
            }
            selectedAnnotationId = nil
        }
    }
    
    private func handleCancel() {
        sessionState = .cropping
        finalRect = nil
        startPoint = nil
        currentPoint = nil
        annotations.removeAll()
    }
    
    private func handleSelectedToolChanged(_ newTool: AnnotationToolType) {
        if editingTextId != nil {
            if let index = annotations.firstIndex(where: { $0.id == editingTextId }) {
                let text = annotations[index].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    annotations.remove(at: index)
                }
            }
            editingTextId = nil
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
        
        let cleanCropped = capture.image.cropping(to: cropRect)!
        let shiftedAnnotations = offsetAnnotations(annotations, by: rect.origin)
        
        let exportView = AnnotationCanvasLayer(
            image: cleanCropped,
            displaySize: CGSize(width: rect.width, height: rect.height),
            annotations: shiftedAnnotations,
            currentAnnotation: nil
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale
        
        guard let finalCropped = renderer.cgImage else {
            print("❌ [OverlayView] 标注合并渲染失败")
            onCanceled()
            return
        }
        
        onCaptured(finalCropped, cleanCropped, shiftedAnnotations, action)
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
        
        let cleanCropped = capture.image.cropping(to: cropRect)!
        let shiftedAnnotations = offsetAnnotations(annotations, by: rect.origin)
        
        let exportView = AnnotationCanvasLayer(
            image: cleanCropped,
            displaySize: CGSize(width: rect.width, height: rect.height),
            annotations: shiftedAnnotations,
            currentAnnotation: nil
        )
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale
        
        if let cgImage = renderer.cgImage {
            PinManager.shared.pin(image: cgImage)
            onCaptured(cgImage, cleanCropped, shiftedAnnotations, .none)
        }
    }
}

/// 统一的悬浮双层工具栏
struct UnifiedToolbarView: View {
    @Binding var selectedTool: AnnotationToolType
    @Binding var selectedColor: Color
    @Binding var selectedSize: CGFloat
    @Binding var selectedTextStyle: TextStyle
    
    var showTextStylePicker: Bool {
        selectedTool == .text || selectedTool == .numberedText
    }
    
    let hasUndo: Bool
    let hasRedo: Bool
    let hasSelection: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    let colors: [Color] = [.red, .blue, .green, .yellow, .white, .black]
    
    var body: some View {
        VStack(spacing: 0) {
            // 第一层：工具栏选择区与操作区
            HStack(spacing: 12) {
                // 1. Shapes 组
                HStack(spacing: 6) {
                    GroupButton(tool: .rectangle, selected: $selectedTool)
                    GroupButton(tool: .filledRectangle, selected: $selectedTool)
                    GroupButton(tool: .ellipse, selected: $selectedTool)
                    GroupButton(tool: .line, selected: $selectedTool)
                    GroupButton(tool: .arrow, selected: $selectedTool)
                }
                
                Text("|").foregroundColor(.gray.opacity(0.4)).padding(.horizontal, 2)
                
                // 2. Text 组
                HStack(spacing: 6) {
                    GroupButton(tool: .text, selected: $selectedTool)
                    GroupButton(tool: .numberedText, selected: $selectedTool)
                    GroupButton(tool: .counter, selected: $selectedTool)
                }
                
                Text("|").foregroundColor(.gray.opacity(0.4)).padding(.horizontal, 2)
                
                // 3. Effects 组
                HStack(spacing: 6) {
                    GroupButton(tool: .pencil, selected: $selectedTool)
                    GroupButton(tool: .highlighter, selected: $selectedTool)
                    GroupButton(tool: .blur, selected: $selectedTool)
                    GroupButton(tool: .mosaic, selected: $selectedTool)
                    GroupButton(tool: .spotlight, selected: $selectedTool)
                }
                
                Spacer() // 将操作组推到最右侧
                
                // 4. 确认取消组
                HStack(spacing: 8) {
                    
                    // Cancel
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("取消 (Esc)")
                    
                    // Confirm
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("完成并保存")
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
                                        .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                )
                                .shadow(radius: selectedColor == color ? 2 : 0)
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    
                    // 尺寸调节滑块
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Slider(value: $selectedSize, in: 2...64, step: 1)
                            .frame(width: 100)
                        Text("\(Int(selectedSize))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }
                    
                    // 文字样式
                    if showTextStylePicker {
                        Picker("", selection: $selectedTextStyle) {
                            ForEach(TextStyle.allCases, id: \.self) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 110)
                    }
                    
                    Spacer()
                    
                    // 5. 进阶操作组
                    HStack(spacing: 8) {
                        // Undo
                        Button(action: onUndo) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(hasUndo ? .white : .gray)
                                .frame(width: 28, height: 28)
                                .background(hasUndo ? Color.blue.opacity(0.85) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .disabled(!hasUndo)
                        .buttonStyle(PlainButtonStyle())
                        .help("撤销 (Cmd+Z)")
                        
                        // Redo
                        Button(action: onRedo) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(hasRedo ? .white : .gray)
                                .frame(width: 28, height: 28)
                                .background(hasRedo ? Color.blue.opacity(0.85) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .disabled(!hasRedo)
                        .buttonStyle(PlainButtonStyle())
                        .help("重做 (Cmd+Shift+Z)")
                        
                        // Pin
                        Button(action: onPin) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.orange.opacity(0.85))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("置顶贴图 (Pin)")
                        
                        // Translate
                        Button(action: onTranslate) {
                            Image(systemName: "translate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.purple.opacity(0.85))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("翻译选区 (Translate)")
                        
                        // OCR
                        Button(action: onOCR) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.indigo.opacity(0.85))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("提取文字 (OCR)")
                        
                        // Delete
                        if hasSelection {
                            Button(action: onDelete) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.red.opacity(0.85))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("删除选中标注 (Delete)")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
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
    
    var isCustomSVG: Bool {
        tool == .pencil || tool == .highlighter || tool == .mosaic || tool == .spotlight
    }
    
    var customSVGPath: String {
        switch tool {
        case .pencil: return SVGPaths.pencil
        case .highlighter: return SVGPaths.highlighter
        case .mosaic: return SVGPaths.mosaic
        case .spotlight: return SVGPaths.spotlight
        default: return ""
        }
    }
    
    var iconName: String {
        switch tool {
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "t.square"
        case .numberedText: return "list.number"
        case .counter: return "1.circle"
        case .pencil: return "paintbrush.pointed"
        case .highlighter: return "marker.fill"
        case .blur: return "drop"
        case .mosaic: return "square.grid.3x3.topleft.filled"
        case .spotlight: return "theatermasks"
        default: return ""
        }
    }
    
    var toolName: String {
        switch tool {
        case .rectangle: return "矩形"
        case .filledRectangle: return "填充矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .text: return "文本"
        case .numberedText: return "带序号文本"
        case .counter: return "序号"
        case .pencil: return "铅笔"
        case .highlighter: return "高亮"
        case .blur: return "模糊"
        case .mosaic: return "马赛克"
        case .spotlight: return "聚焦"
        }
    }
    
    var body: some View {
        Button(action: {
            selected = tool
        }) {
            Group {
                if isCustomSVG {
                    SVGIconView(pathData: customSVGPath, color: isSelected ? .white : .primary)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                }
            }
            .frame(width: 32, height: 32)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(6)
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
