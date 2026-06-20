import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import Translation


/// 由 AutoSizingTextView 的 Coordinator 触发的编辑提交通知，
/// 避免在 NSTextView 回调 closure 中直接捕获 AnnotationRootView / OverlayRootView 实例导致闪崩。
let commitTextEditNotification = Notification.Name("AnnotationCommitTextEdit")

/// 标注画布视图
public struct AnnotationRootView: View {
    let image: CGImage
    let originalSize: CGSize
    @State private var recordId: UUID?
    let onClose: () -> Void
    
    @State private var annotations: [AnnotationItem] = []
    @State private var currentAnnotation: AnnotationItem? = nil
    @State private var editingTextId: UUID? = nil
    @State private var editingCounterId: UUID? = nil
    @State private var selectedOCRBlockId: UUID? = nil
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    
    @State private var selectedTool: AnnotationToolType = .aiMarker
    @State private var selectedColor: Color = TMDesign.Colors.red
    
    @State private var selectedFontSize: CGFloat = 16.0
    @State private var selectedLineWidth: CGFloat = 4.0
    @State private var selectedBrushSize: CGFloat = 24.0
    @State private var selectedTextStyle: TextStyle = .standard

    /// 工具切换的自定义 Binding：切换工具前通过通知异步提交编辑态，
    /// 避免 closure 直接捕获 AnnotationRootView 实例方法导致闪崩。
    private var selectedToolBinding: Binding<AnnotationToolType> {
        Binding(
            get: { selectedTool },
            set: { newTool in
                guard newTool != selectedTool else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: commitTextEditNotification, object: nil)
                }
                selectedTool = newTool
            }
        )
    }

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
    
    // 双击检测状态
    @State private var lastClickTime: Double = 0
    @State private var lastClickAnnotationId: UUID? = nil
    
    @State private var dragStartPos: CGPoint? = nil
    @State private var dragStartClickCount: Int = 1
    @State private var lastDragPoint: CGPoint? = nil
    
    // OCR & Translation 状态
    @State private var ocrResultText: String = ""
    @State private var showOCRPanel: Bool = false
    @State private var showTranslationSidebar: Bool = false
    @State private var isOCRLoading: Bool = false
    @State private var isTranslating: Bool = false
    @State private var ocrTextBlocks: [RecognizedTextBlock] = []
    @State private var isOCREditingMode: Bool = false
    @State private var translatedText: String = ""
    @State private var translationConfiguration: Any? = nil

    public init(
        image: CGImage,
        displaySize: CGSize,
        initialAnnotations: [AnnotationItem] = [],
        recordId: UUID? = nil,
        onClose: @escaping () -> Void
    ) {
        self.image = image
        self.originalSize = displaySize
        self._recordId = State(initialValue: recordId)
        self.onClose = onClose
        self._annotations = State(initialValue: initialAnnotations)
        self._undoStack = State(initialValue: [])
    }
    
    private func commitTextEdit() {
        if let currentEditing = editingTextId {
            if let idx = annotations.firstIndex(where: { $0.id == currentEditing }) {
                if (annotations[idx].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    annotations.remove(at: idx)
                } else {
                    let item = annotations[idx]
                    let fontSize = item.fontSize ?? 16.0
                    let singleLineHeight = fontSize * 1.2 + 16
                    if item.customWidth == nil,
                       (item.text ?? "").contains("\n") || item.rect.height > singleLineHeight + 4 {
                        annotations[idx].customWidth = item.rect.width
                    }
                }
            }
            editingTextId = nil
        }
        if let currentEditingCounter = editingCounterId {
            if let idx = annotations.firstIndex(where: { $0.id == currentEditingCounter }) {
                let newStr = annotations[idx].customCounterString ?? ""
                reorderCounters(after: currentEditingCounter, newString: newStr)
            }
            editingCounterId = nil
        }
    }

    /// 点击空白处提交所有编辑态（counter / text）
    private func commitAllEdits() {
        guard editingTextId != nil || editingCounterId != nil else { return }
        // 先处理数据与排序；编辑态 ID 清空后，AutoSizingTextView.updateNSView
        // 会检测到编辑态结束并安全地辞去 NSTextView 的第一响应者，
        // 避免在 async 通知路径中直接访问可能已释放的 responder。
        commitTextEdit()
    }
    
    private func deleteSelectedAnnotation() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }
        
        prepareForWrite()
        let deletedItem = annotations[index]
        annotations.remove(at: index)
        
        // 序号顺延算法 (Phase 2)
        if (deletedItem.type == .counter || deletedItem.type == .numberedText),
           let deletedValue = deletedItem.counterValue {
            for i in 0..<annotations.count {
                if (annotations[i].type == .counter || annotations[i].type == .numberedText),
                   let val = annotations[i].counterValue, val > deletedValue {
                    annotations[i].counterValue = val - 1
                }
            }
        }
        
        selectedAnnotationId = nil
    }
    
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
        annotations = undoStack.removeLast()
    }
    
    private func reorderCounters(after id: UUID, newString: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let counterIndices = annotations.enumerated().compactMap { $0.element.type == .counter || $0.element.type == .numberedText ? $0.offset : nil }
        guard let position = counterIndices.firstIndex(of: index) else { return }

        prepareForWrite()

        // 仅正整数生效；超出范围时钳位到 [1, total]
        if let newIntValue = Int(newString), newIntValue > 0 {
            let total = counterIndices.count
            let clampedValue = max(1, min(newIntValue, total))
            let targetPosition = clampedValue - 1

            // 按创建顺序（数组下标）取出所有 counter 的 id
            var orderedIds = counterIndices.map { annotations[$0].id }
            let movedId = orderedIds.remove(at: position)
            orderedIds.insert(movedId, at: targetPosition)
            for (newPos, cid) in orderedIds.enumerated() {
                if let idx = annotations.firstIndex(where: { $0.id == cid }) {
                    annotations[idx].counterValue = newPos + 1
                    annotations[idx].customCounterString = nil
                }
            }
        } else {
            // 非法输入：回退显示字符串，不进行任何排序变更
            annotations[index].customCounterString = nil
        }
    }
    
    public var body: some View {
        let content = HStack(spacing: 0) {
            ZStack {
            VStack(spacing: 0) {
                // 核心画布区
                GeometryReader { containerGeo in
                    let scaleX = containerGeo.size.width / originalSize.width
                    let scaleY = containerGeo.size.height / originalSize.height
                    let scale = min(scaleX, scaleY)
                    
                    let canvasWidth = originalSize.width * scale
                    let canvasHeight = originalSize.height * scale
                    let offsetX = (containerGeo.size.width - canvasWidth) / 2
                    let offsetY = (containerGeo.size.height - canvasHeight) / 2
                    
                    let mapPoint = { (pt: CGPoint) -> CGPoint in
                        let localX = (pt.x - offsetX) / scale
                        let localY = (pt.y - offsetY) / scale
                        return CGPoint(
                            x: max(0, min(originalSize.width, localX)),
                            y: max(0, min(originalSize.height, localY))
                        )
                    }
                    
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                            .onTapGesture {
                                // 点击空白处时先提交所有编辑态，再清空选中
                                commitAllEdits()
                                selectedAnnotationId = nil
                            }
                            
                        // Canvas is exactly the visual size, placed at offset
                        AnnotationCanvasLayer(
                            image: image,
                            displaySize: originalSize,
                            annotations: annotations,
                            currentAnnotation: currentAnnotation,
                            selectedAnnotationId: selectedAnnotationId,
                            editingTextId: editingTextId,
                            editingCounterId: editingCounterId,
                            onTextChanged: { id, newText in
                                if let index = annotations.firstIndex(where: { $0.id == id }) {
                                    annotations[index].text = newText
                                }
                            },
                            onTextCommit: {
                                // 防止 textDidEndEditing 与点击空白导致的重复提交
                                if editingTextId != nil || editingCounterId != nil {
                                    commitAllEdits()
                                }
                            },

                            onCounterChanged: { id, str in
                                if let index = annotations.firstIndex(where: { $0.id == id }) {
                                    annotations[index].customCounterString = str
                                }
                            },
                            onSizeChanged: { id, size in
                                DispatchQueue.main.async {
                                    if let index = annotations.firstIndex(where: { $0.id == id }) {
                                        let item = annotations[index]
                                        let offset = item.calloutOffset ?? (item.type == .numberedText ? CGSize(width: 16.0, height: -45.0) : .zero)
                                        let endX = item.startPoint.x + offset.width + size.width
                                        let endY = item.startPoint.y + offset.height + size.height
                                        if item.endPoint.x != endX || item.endPoint.y != endY {
                                            annotations[index].endPoint = CGPoint(x: endX, y: endY)
                                        }
                                    }
                                }
                            }
                        )
                        .frame(width: originalSize.width, height: originalSize.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                        .offset(x: offsetX, y: offsetY)
                        .allowsHitTesting(!isOCREditingMode)

                        // OCR 编辑态时不渲染 MouseTrackingView，避免其 NSView 拦截 OCR 文本视图的事件
                        if !isOCREditingMode {
                            MouseTrackingView(
                                onDragStart: { pt, clickCount in handleDragStart(mapPoint(pt), clickCount: clickCount) },
                                onDragChange: { pt in handleDragChange(mapPoint(pt)) },
                                onDragEnd: handleDragEnd,
                                onCancel: onClose,
                                onHover: { pt in
                                    let localX = (pt.x - offsetX) / scale
                                    let localY = (pt.y - offsetY) / scale
                                    let isInside = localX >= 0 && localX <= originalSize.width && localY >= 0 && localY <= originalSize.height
                                    
                                    if isInside {
                                        hoverPoint = pt
                                        isHoveringCanvas = true
                                        handleHover(mapPoint(pt))
                                    } else {
                                        isHoveringCanvas = false
                                        NSCursor.arrow.set()
                                    }
                                },
                                onHoverExited: {
                                    isHoveringCanvas = false
                                    NSCursor.arrow.set()
                                },
                                activeTool: selectedTool,
                                onUndo: undo,
                                onRedo: redo,
                                onDelete: deleteSelectedAnnotation,
                                annotations: annotations,
                                mapPoint: mapPoint
                            )
                            .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                            .allowsHitTesting(editingTextId == nil && editingCounterId == nil && !isOCREditingMode)
                        }

                        // OCR 编辑态：在图片上方叠加可选择文本层
                        if isOCREditingMode {
                            let ocrDisplaySize = CGSize(width: canvasWidth, height: canvasHeight)
                            OCRTextOverlayView(textBlocks: ocrTextBlocks, displaySize: ocrDisplaySize, selectedBlockId: $selectedOCRBlockId)
                                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                                .offset(x: offsetX, y: offsetY)

                            // OCR 模式状态标签：置于画布外，避免遮挡图片内容
                            VStack {
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.viewfinder")
                                            .font(.system(size: 9, weight: .semibold))
                                        Text("OCR · 拖拽选择文本")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.55))
                                    .cornerRadius(10)
                                    .allowsHitTesting(false)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(.top, 8)
                            .padding(.leading, 8)
                            .allowsHitTesting(false)
                        }

                        // 7. PSD-style 圆形画笔光标
                        let isBrush = [AnnotationToolType.pencil, .highlighter, .blur, .mosaic].contains(selectedTool)
                        if isHoveringCanvas && isBrush {
                            BrushCursorView(
                                selectedTool: selectedTool,
                                selectedLineWidth: selectedLineWidth,
                                scale: scale
                            )
                        }
                    }
                    .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                }
                .clipped()
                
                // 双层工具栏
                toolbarLayer
            }
            
            
            // 隐藏的撤销重做快捷键支持
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

            // OCR 编辑态下按 Esc 退出
            Button("") { isOCREditingMode = false }
                .keyboardShortcut(.escape)
                .opacity(0)
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)

            // 成功提示 Toast
            if showToast {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                    Text(toastMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
            
            // 提取文字面板被移到 HStack 侧边栏
            
            
            // OCR 加载状态
            if isOCRLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .padding(24)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                    .zIndex(102)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if showOCRPanel {
                Divider().background(Color.black.opacity(0.5))
                OCRResultPanel(
                    text: $ocrResultText,
                    textBlocks: ocrTextBlocks,
                    imageSize: CGSize(width: image.width, height: image.height),
                    selectedBlockId: $selectedOCRBlockId,
                    onClose: {
                        withAnimation { showOCRPanel = false }
                    })
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }

            if showTranslationSidebar {
                Divider().background(Color.black.opacity(0.5))
                TranslationSidebarView(
                    sourceText: ocrResultText,
                    translatedText: $translatedText,
                    isLoading: isTranslating,
                    onClose: {
                        withAnimation { showTranslationSidebar = false }
                    },
                    onRetranslate: {
                        performTranslation()
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerPostCaptureAction"))) { notification in
            if let action = notification.object as? PostCaptureAction {
                if action == .ocr {
                    performOCR(isForTranslation: false)
                } else if action == .translate {
                    performOCR(isForTranslation: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CounterDoubleTapped"))) { notification in
            if let id = notification.object as? UUID {
                editingCounterId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: commitTextEditNotification)) { _ in
            if editingTextId != nil || editingCounterId != nil {
                commitAllEdits()
            }
        }
        .onChange(of: selectedColor) { newColor in
            updateSelectedAnnotation(color: newColor)
        }
        .onChange(of: selectedFontSize) { newSize in
            updateSelectedAnnotation(fontSize: newSize)
        }
        .onChange(of: selectedLineWidth) { newSize in
            updateSelectedAnnotation(lineWidth: newSize)
        }
        .onChange(of: selectedTextStyle) { newStyle in
            updateSelectedAnnotation(style: newStyle)
        }
        .onChange(of: selectedAnnotationId) { newId in
            handleSelectionChange(to: newId)
        }
        .onChange(of: isOCREditingMode) { newValue in
            // OCR 编辑态需要禁用窗口背景拖拽，否则拖扫文字会变成拖拽窗口
            if let window = NSApp.keyWindow as? AnnotationWindow {
                window.isMovableByWindowBackground = !newValue
            }
        }

        if #available(macOS 15.0, *) {
            let config = translationConfiguration as? TranslationSession.Configuration
            content.translationTask(config) { session in
                guard !ocrResultText.isEmpty else { return }
                do {
                    let response = try await session.translate(ocrResultText)
                    translatedText = response.targetText
                } catch {
                    print("❌ [Translation] 翻译失败: \(error)")
                    translatedText = "翻译失败：\(error.localizedDescription)"
                }
                isTranslating = false
            }
        } else {
            content
        }
    }

// MARK: - Interaction Handlers
    
    private let handleHitZone: CGFloat = 20.0
    
    private func hitTestHandle(point: CGPoint, rect: CGRect) -> DragHandle? {
        let hitRect = rect.insetBy(dx: -handleHitZone, dy: -handleHitZone)
        guard hitRect.contains(point) else { return nil }
        
        let p = point
        let hitZoneX = min(self.handleHitZone, max(10, rect.width / 3.0))
        let hitZoneY = min(self.handleHitZone, max(10, rect.height / 3.0))
        
        let isNearX = { (val: CGFloat, target: CGFloat) in abs(val - target) <= hitZoneX }
        let isNearY = { (val: CGFloat, target: CGFloat) in abs(val - target) <= hitZoneY }
        
        if isNearX(p.x, rect.minX) && isNearY(p.y, rect.minY) { return .topLeft }
        if isNearX(p.x, rect.maxX) && isNearY(p.y, rect.minY) { return .topRight }
        if isNearX(p.x, rect.minX) && isNearY(p.y, rect.maxY) { return .bottomLeft }
        if isNearX(p.x, rect.maxX) && isNearY(p.y, rect.maxY) { return .bottomRight }
        if isNearX(p.x, rect.minX) { return .left }
        if isNearX(p.x, rect.maxX) { return .right }
        if isNearY(p.y, rect.minY) { return .top }
        if isNearY(p.y, rect.maxY) { return .bottom }
        return nil
    }
    
    private func isPointInNumberedCircle(_ point: CGPoint, item: AnnotationItem) -> Bool {
        guard item.type == .numberedText else { return false }
        let size = (item.fontSize ?? 16.0) * 1.5
        let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
        return circleRect.contains(point)
    }

    private func hitTestAnnotation(point: CGPoint) -> (UUID, DragHandle?)? {
        // 检查是否点中了 NumberedText 的起始点圆圈
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let item = annotations[index]
            if item.type == .numberedText {
                let size = (item.fontSize ?? 16.0) * 1.5
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(point) {
                    return (selectedId, .calloutOrigin)
                }
            }
        }
        
        // 先检查是否点中了某个控制柄（文本框控制柄）
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let itemRect = annotations[index].rect
            let itemType = annotations[index].type
            let isText = itemType == .text || itemType == .numberedText || itemType == .rectText

            if let handle = hitTestHandle(point: point, rect: itemRect) {
                if isText {
                    let hitZoneX: CGFloat = 10.0
                    if abs(point.x - itemRect.minX) <= hitZoneX { return (selectedId, .left) }
                    if abs(point.x - itemRect.maxX) <= hitZoneX { return (selectedId, .right) }
                    // 忽略其它控制柄，允许点击中心拖拽整体
                    return (selectedId, nil)
                } else {
                    return (selectedId, handle)
                }
            }
        }

        // 检查选中的 RectText 的矩形框（优先级高于文本框，便于拖拽整体）
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }),
           let rectBounds = rectTextBounds(annotations[index]),
           rectBounds.contains(point) {
            return (selectedId, .calloutOrigin)
        }

        // 检查未选中的 NumberedText 的起始点圆圈
        for item in annotations.reversed() {
            if item.type == .numberedText {
                let size = (item.fontSize ?? 16.0) * 1.5
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(point) {
                    return (item.id, .calloutOrigin)
                }
            }
        }

        // 检查未选中的 RectText 的矩形框
        for item in annotations.reversed() {
            if let rectBounds = rectTextBounds(item), rectBounds.contains(point) {
                return (item.id, .calloutOrigin)
            }
        }

        // 再检查是否点中了某个标注的包围盒（文本框或其他形状）
        for item in annotations.reversed() {
            if item.rect.contains(point) {
                return (item.id, nil)
            }
        }
        
        return nil
    }
    
    private func handleHover(_ point: CGPoint) {
        // 用户要求统一为箭头光标，彻底解决闪烁与割裂感
        NSCursor.arrow.set()
    }
    
    private func handleDragStart(_ point: CGPoint, clickCount: Int) {
        dragStartClickCount = clickCount
        dragStartPos = point
        lastDragPoint = point
        let now = ProcessInfo.processInfo.systemUptime
        let clickInterval = now - lastClickTime
        lastClickTime = now
        
        if let (id, handle) = hitTestAnnotation(point: point) {
            // 如果点中其他元素，先统一提交当前编辑态
            if (editingTextId != nil && editingTextId != id) || (editingCounterId != nil && editingCounterId != id) {
                commitAllEdits()
            }

            prepareForWrite()
            selectedAnnotationId = id
            annotationActiveHandle = handle
            annotationInitialItem = annotations.first(where: { $0.id == id })
            annotationDragStartPoint = point
            
            // 双击进入编辑态：支持文本框、带序号文本、矩形框文本，以及双击序号圆圈。
            // 条件放宽：系统 clickCount 不可靠或用户双击稍慢时，用 lastClickAnnotationId + 0.5s 兜底。
            if clickCount >= 2 || (lastClickAnnotationId == id && clickInterval < 0.5) {
                let item = annotations.first(where: { $0.id == id })
                // 优先判断：如果命中带序号文本的序号圆圈，进入序号编辑（即使 hitTest 返回文本框）
                if let item = item, item.type == .numberedText, isPointInNumberedCircle(point, item: item) {
                    editingCounterId = id
                } else if item?.type == .text || item?.type == .numberedText || item?.type == .rectText {
                    editingTextId = id
                } else if item?.type == .counter {
                    editingCounterId = id
                }
            }
            lastClickAnnotationId = id
            return
        }
        
        lastClickAnnotationId = nil
        selectedAnnotationId = nil
        
        commitAllEdits()
        
        if selectedTool == .text || selectedTool == .numberedText {
            prepareForWrite()
            var cValue: Int? = nil
            if selectedTool == .numberedText {
                cValue = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
            }
            let textItem = AnnotationItem(type: selectedTool, startPoint: point, endPoint: point, color: selectedColor, lineWidth: 2.0, text: "", fontStyle: selectedTextStyle, fontSize: selectedFontSize, counterValue: cValue)
            annotations.append(textItem)
            editingTextId = textItem.id
        } else {
            if currentAnnotation == nil {
                prepareForWrite()
                var cValue: Int? = nil
                if selectedTool == .aiMarker {
                    cValue = annotations.filter { $0.type == .aiMarker }.count + 1
                } else if selectedTool == .counter || selectedTool == .numberedText {
                    cValue = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
                }
                
                let markerColor = selectedTool == .aiMarker ? TMDesign.Colors.purple.opacity(0.7) : selectedColor
                let isThickBrush = selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic
                let lw = isThickBrush ? selectedBrushSize : selectedLineWidth
                var newAnnotation = AnnotationItem(type: selectedTool, startPoint: point, endPoint: point, color: markerColor, lineWidth: lw, fontStyle: selectedTextStyle, fontSize: selectedFontSize, counterValue: cValue)
                if selectedTool == .rectText { newAnnotation.points = [point, point] }
                if newAnnotation.isFreehandTool { newAnnotation.points = [point] }
                currentAnnotation = newAnnotation
            }
            if currentAnnotation?.type == .rectText {
                currentAnnotation?.points?[1] = point
                currentAnnotation?.endPoint = point
            } else if currentAnnotation?.isFreehandTool == true {
                currentAnnotation?.points?.append(point)
                currentAnnotation?.endPoint = point
            } else {
                currentAnnotation?.endPoint = point
            }
        }
    }
    
    private func handleDragChange(_ point: CGPoint) {
        lastDragPoint = point
        let canvasBounds = CGRect(origin: .zero, size: originalSize)
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }),
           let initialItem = annotationInitialItem,
           let start = annotationDragStartPoint {

            let dx = point.x - start.x
            let dy = point.y - start.y
            var updatedItem = initialItem

            if let handle = annotationActiveHandle {
                if handle == .calloutOrigin {
                    updatedItem.move(by: CGSize(width: dx, height: dy))
                } else {
                    let initRect = initialItem.rect
                    var newRect = initRect
                    switch handle {
                    case .left: newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx); newRect.size.width = initRect.maxX - newRect.origin.x
                    case .right: newRect.size.width = max(5, initRect.size.width + dx)
                    case .top: newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy); newRect.size.height = initRect.maxY - newRect.origin.y
                    case .bottom: newRect.size.height = max(5, initRect.size.height + dy)
                    case .topLeft: newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx); newRect.size.width = initRect.maxX - newRect.origin.x; newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy); newRect.size.height = initRect.maxY - newRect.origin.y
                    case .topRight: newRect.size.width = max(5, initRect.size.width + dx); newRect.origin.y = min(initRect.maxY - 5, initRect.origin.y + dy); newRect.size.height = initRect.maxY - newRect.origin.y
                    case .bottomLeft: newRect.origin.x = min(initRect.maxX - 5, initRect.origin.x + dx); newRect.size.width = initRect.maxX - newRect.origin.x; newRect.size.height = max(5, initRect.size.height + dy)
                    case .bottomRight: newRect.size.width = max(5, newRect.size.width + dx); newRect.size.height = max(5, newRect.size.height + dy)
                    case .calloutOrigin: break
                    }
                    updatedItem.resize(to: newRect, from: initRect)
                }
            } else {
                if updatedItem.type == .numberedText || updatedItem.type == .rectText {
                    let oldOffset = updatedItem.calloutOffset ?? (updatedItem.type == .rectText ? .zero : CGSize(width: 16.0, height: -45.0))
                    updatedItem.calloutOffset = CGSize(width: oldOffset.width + dx, height: oldOffset.height + dy)
                    updatedItem.endPoint = CGPoint(x: updatedItem.endPoint.x + dx, y: updatedItem.endPoint.y + dy)
                } else {
                    updatedItem.move(by: CGSize(width: dx, height: dy))
                }
            }
            annotations[index] = clampedAnnotation(updatedItem, to: canvasBounds)
            return
        }

        if selectedTool != .text {
            if var current = currentAnnotation, current.isFreehandTool {
                var clampedPoint = point
                if !canvasBounds.isEmpty, !canvasBounds.contains(point) {
                    clampedPoint = CGPoint(
                        x: min(max(point.x, canvasBounds.minX), canvasBounds.maxX),
                        y: min(max(point.y, canvasBounds.minY), canvasBounds.maxY)
                    )
                }
                if current.points == nil { current.points = [] }
                if let lastPoint = current.points?.last {
                    let distance = hypot(clampedPoint.x - lastPoint.x, clampedPoint.y - lastPoint.y)
                    if distance > 3.0 {
                        current.points?.append(clampedPoint)
                        current.endPoint = clampedPoint
                    }
                } else {
                    current.points?.append(clampedPoint)
                    current.endPoint = clampedPoint
                }
                currentAnnotation = current
            } else if currentAnnotation?.type == .rectText {
                currentAnnotation?.points?[1] = point
                currentAnnotation?.endPoint = point
            } else {
                currentAnnotation?.endPoint = point
            }
        }
    }
    
    private func handleDragEnd() {
        if let startPos = dragStartPos, let lastPos = lastDragPoint, let selectedId = selectedAnnotationId, let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let dx = abs(lastPos.x - startPos.x)
            let dy = abs(lastPos.y - startPos.y)
            let isText = annotations[index].type == .text || annotations[index].type == .numberedText || annotations[index].type == .rectText
            let isCounter = annotations[index].type == .counter
            if isText && dx < 5 && dy < 5 && dragStartClickCount >= 2 {
                prepareForWrite()
                editingTextId = selectedId
            } else if isCounter && dx < 5 && dy < 5 && dragStartClickCount >= 2 {
                editingCounterId = selectedId
            }
        }
        dragStartPos = nil
        lastDragPoint = nil
        
        if annotationInitialItem != nil {
            let changed = (undoStack.last != annotations)
            annotationInitialItem = nil
            annotationDragStartPoint = nil
            annotationActiveHandle = nil
            if !changed { if !undoStack.isEmpty { _ = undoStack.removeLast() } }
            return
        }
        
        if selectedTool != .text {
            if let final = currentAnnotation {
                var shouldSave = false
                if final.isFreehandTool {
                    if let points = final.points, points.count > 3 { annotations.append(final); shouldSave = true }
                } else {
                    let dx = abs(final.startPoint.x - final.endPoint.x)
                    let dy = abs(final.startPoint.y - final.endPoint.y)
                    if final.type == .counter || final.type == .aiMarker || dx > 5 || dy > 5 { annotations.append(final); shouldSave = true }
                }
                if shouldSave, final.type == .rectText, let idx = annotations.indices.last {
                    let p0 = annotations[idx].points?[0] ?? annotations[idx].startPoint
                    let p1 = annotations[idx].points?[1] ?? annotations[idx].endPoint
                    let minX = min(p0.x, p1.x)
                    let maxX = max(p0.x, p1.x)
                    let minY = min(p0.y, p1.y)
                    let maxY = max(p0.y, p1.y)
                    let rectWidth = maxX - minX
                    annotations[idx].points = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)]
                    annotations[idx].startPoint = CGPoint(x: minX, y: minY)
                    let offset = CGSize(width: rectWidth + 16, height: 0)
                    annotations[idx].calloutOffset = offset
                    annotations[idx].endPoint = CGPoint(x: minX + offset.width + 120, y: minY + offset.height + 30)
                    annotations[idx].customWidth = 120
                    selectedAnnotationId = annotations[idx].id
                    editingTextId = annotations[idx].id
                }
                if !shouldSave { if !undoStack.isEmpty { _ = undoStack.removeLast() } }
            }
            currentAnnotation = nil
        }
    }
    
    /// 将标注整体平移，使其包围盒不超出 bounds（用于拖拽/缩放后兜底，不裁剪内容）。
    private func clampedAnnotation(_ item: AnnotationItem, to bounds: CGRect) -> AnnotationItem {
        guard bounds.width > 0, bounds.height > 0 else { return item }
        var item = item
        let boundingRect = item.rect
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if boundingRect.minX < bounds.minX { dx = bounds.minX - boundingRect.minX }
        if boundingRect.minY < bounds.minY { dy = bounds.minY - boundingRect.minY }
        if boundingRect.maxX > bounds.maxX { dx = bounds.maxX - boundingRect.maxX }
        if boundingRect.maxY > bounds.maxY { dy = bounds.maxY - boundingRect.maxY }
        if dx != 0 || dy != 0 {
            item.move(by: CGSize(width: dx, height: dy))
        }
        return item
    }

    private func updateSelectedAnnotation(color: Color? = nil, fontSize: CGFloat? = nil, lineWidth: CGFloat? = nil, style: TextStyle? = nil) {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }
        
        var item = annotations[index]
        var changed = false
        
        if let newColor = color, item.color != newColor {
            item.color = newColor
            changed = true
        }
        
        if let newSize = fontSize {
            if item.fontSize != newSize {
                item.fontSize = newSize
                changed = true
            }
        }
        
        if let newWidth = lineWidth {
            if item.lineWidth != newWidth {
                item.lineWidth = newWidth
                changed = true
            }
        }
        
        if let newStyle = style, (item.type == .text || item.type == .numberedText || item.type == .rectText) {
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
        if item.type == .text || item.type == .numberedText || item.type == .rectText || item.type == .counter || item.type == .aiMarker {
            selectedFontSize = item.fontSize ?? 16.0
        } else {
            selectedLineWidth = item.lineWidth
        }
        if let style = item.fontStyle {
            selectedTextStyle = style
        }
    }
    
    @MainActor
    private func pinScreenshot() {
        let exportView = AnnotationCanvasLayer(
            image: image,
            displaySize: originalSize,
            annotations: annotations,
            currentAnnotation: nil
        )
        let renderer = ImageRenderer(content: exportView)
        let scaleFactor = CGFloat(image.width) / originalSize.width
        renderer.scale = scaleFactor
        
        if let rendered = renderer.cgImage,
           let alphaFixed = ensurePremultipliedAlpha(for: rendered),
           let cgImage = applyAlphaMask(from: image, to: alphaFixed) {
            PinManager.shared.pin(image: cgImage)
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: annotations, finalImage: cgImage)
            } else {
                CaptureEngine.shared.saveToDisk(image: cgImage, originalImage: image, fileName: "Screenshot_Annotated", annotations: annotations)
                if let newRecordId = HistoryManager.shared.records.first?.id {
                    recordId = newRecordId
                }
            }

            onClose()
        }
    }
    
    private func exportToAI(copyCoords: Bool) {
        if let cleanImageForClipboard = generateImageForExport(excludeAIMarkers: true),
           let fullImageForHistory = generateImageForExport(excludeAIMarkers: false) {
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            var itemsToWrite: [NSPasteboardWriting] = []
            let aiMarkers = annotations.filter { $0.type == .aiMarker }
            
            if !copyCoords {
                // 仅复制原图，使用与保存一致的 PNG 编码保留 alpha
                let imageItem = NSPasteboardItem()
                if let pngData = CaptureEngine.shared.pngData(from: cleanImageForClipboard) {
                    imageItem.setData(pngData, forType: .png)
                }
                itemsToWrite.append(imageItem)
            } else {
                // 仅复制文本坐标
                if !aiMarkers.isEmpty {
                    let textItem = NSPasteboardItem()
                    var textOutput = LanguageManager.shared.localizedString(forKey: "以下是在原图上圈出的目标元素坐标 [xmin, ymin, xmax, ymax]，请逐一根据坐标和关联的要求修改：") + "\n"
                    
                    let scaleX = CGFloat(image.width) / originalSize.width
                    let scaleY = CGFloat(image.height) / originalSize.height
                    
                    for marker in aiMarkers.sorted(by: { ($0.counterValue ?? 0) < ($1.counterValue ?? 0) }) {
                        let idStr = marker.displayCounterString
                        let rect = marker.rect
                        let realX = Int(rect.minX * scaleX)
                        let realY = Int(rect.minY * scaleY)
                        let realMaxX = Int(rect.maxX * scaleX)
                        let realMaxY = Int(rect.maxY * scaleY)
                        let absStr = "[\(realX), \(realY), \(realMaxX), \(realMaxY)]"
                        textOutput += "\(idStr). \(absStr)\n"
                    }
                    textItem.setString(textOutput, forType: .string)
                    itemsToWrite.append(textItem)
                }
            }
            
            pasteboard.writeObjects(itemsToWrite)
            print("📋 [Annotation] AI \(copyCoords ? "坐标" : "原图")已复制")
            
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: annotations, finalImage: fullImageForHistory)
            } else {
                CaptureEngine.shared.saveToDisk(image: fullImageForHistory, originalImage: image, fileName: "Screenshot_Annotated", annotations: annotations)
                if let newRecordId = HistoryManager.shared.records.first?.id {
                    recordId = newRecordId
                }
            }
            
            withAnimation(.spring()) {
                if copyCoords {
                    toastMessage = LanguageManager.shared.localizedString(forKey: "已保存并复制 AI 定位坐标")
                } else {
                    toastMessage = LanguageManager.shared.localizedString(forKey: "已保存并复制原图")
                }
                showToast = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring()) {
                    showToast = false
                }
            }
        }
    }
    
    @MainActor
    private func copyToClipboard() {
        if let cgImage = generateImageForExport(excludeAIMarkers: true) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            let pbItem = NSPasteboardItem()
            if let pngData = CaptureEngine.shared.pngData(from: cgImage) {
                pbItem.setData(pngData, forType: .png)
                // PNG 优先以保留 alpha；NSImage 作为后备兼容部分应用
                let nsImage = NSImage(data: pngData) ?? NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                pasteboard.writeObjects([pbItem, nsImage])
            } else {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                pasteboard.writeObjects([nsImage])
            }

            print("📋 [Annotation] 普通标注图已复制")
            
            withAnimation(.spring()) {
                toastMessage = LanguageManager.shared.localizedString(forKey: "已复制到剪贴板")
                showToast = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring()) {
                    showToast = false
                }
            }
        }
    }

    @MainActor
    private func exportAndClose() {
        if annotations.isEmpty && currentAnnotation == nil {
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: [], finalImage: image)
            } else {
                CaptureEngine.shared.saveToDisk(image: image, fileName: "Screenshot_Annotated")
            }
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])
            
            print("✅ [Annotation] 标注成功导出并保存！")

            withAnimation(.spring()) {
                toastMessage = LanguageManager.shared.localizedString(forKey: "Saved_And_Copied")
                showToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onClose()
            }
            return
        }

        if let cgImage = generateImageForExport(excludeAIMarkers: true) {
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: annotations, finalImage: cgImage)
            } else {
                CaptureEngine.shared.saveToDisk(image: cgImage, fileName: "Screenshot_Annotated")
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            let pbItem = NSPasteboardItem()
            if let pngData = CaptureEngine.shared.pngData(from: cgImage) {
                pbItem.setData(pngData, forType: .png)
                // PNG 优先以保留 alpha；NSImage 作为后备兼容部分应用
                let nsImage = NSImage(data: pngData) ?? NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                pasteboard.writeObjects([pbItem, nsImage])
            } else {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                pasteboard.writeObjects([nsImage])
            }

            print("✅ [Annotation] 标注成功导出并保存！")

            withAnimation(.spring()) {
                toastMessage = LanguageManager.shared.localizedString(forKey: "Saved_And_Copied")
                showToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onClose()
            }
        } else {
            print("❌ [Annotation] ImageRenderer 渲染失败")
            onClose()
        }
    }
    
    @MainActor
    private func generateImageForExport(excludeAIMarkers: Bool = true) -> CGImage? {
        let exportAnnotations = excludeAIMarkers ? annotations.filter { $0.type != .aiMarker } : annotations
        let scaleFactor = CGFloat(image.width) / originalSize.width
        let hasAlpha = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast ||
                       image.alphaInfo == .first || image.alphaInfo == .last
        let windowCornerRadius: CGFloat = 14.0 * scaleFactor

        // 先同步把 blur/mosaic 画笔效果 burn 到原图上；ImageRenderer 不会等待 ImageEffectView 异步加载，
        // 因此导出前必须预处理，否则模糊/马赛克在复制图片中会丢失。
        let sourceImage = applyBrushEffects(to: image, annotations: exportAnnotations, displaySize: originalSize) ?? image
        let hasBlurMosaic = exportAnnotations.contains { $0.type == .blur || $0.type == .mosaic }

        let exportView = AnnotationCanvasLayer(
            image: sourceImage,
            displaySize: originalSize,
            annotations: exportAnnotations,
            currentAnnotation: nil,
            selectedAnnotationId: nil,
            editingTextId: nil,
            editingCounterId: nil,
            onTextChanged: { _, _ in },
            onTextCommit: {},
            onSizeChanged: { _, _ in },
            skipBlurMosaic: hasBlurMosaic
        )
        .frame(width: originalSize.width, height: originalSize.height, alignment: .topLeading)
        .scaleEffect(scaleFactor, anchor: .topLeading)
        .frame(width: CGFloat(image.width), height: CGFloat(image.height), alignment: .topLeading)

        let renderer = ImageRenderer(content: exportView)
        guard let rendered = renderer.cgImage,
              var alphaFixed = ensurePremultipliedAlpha(for: rendered) else { return nil }

        // 用预处理后的原图 alpha 恢复渲染后图像的圆角透明区域
        if let masked = applyAlphaMask(from: sourceImage, to: alphaFixed) {
            alphaFixed = masked
        }
        // 再次强制透明像素 RGB 归零
        if let cleaned = ensurePremultipliedAlpha(for: alphaFixed) {
            alphaFixed = cleaned
        }
        // 最终兜底：对窗口截图再次应用硬圆角遮罩，清除圆角及四边边缘可能残留的白色/灰色像素
        if hasAlpha {
            alphaFixed = applyWindowCornerMask(to: alphaFixed, cornerRadius: windowCornerRadius, inset: 1.0) ?? alphaFixed
        }
        return alphaFixed
    }

    @MainActor
    private func generateDragURL() -> URL? {
        guard let cgImage = generateImageForExport() else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination) ? tempURL : nil
    }
    
    // MARK: - OCR & Translation
    private func performOCR(isForTranslation: Bool = false) {
        // 如果当前已在 OCR 编辑态且不是翻译操作，则退出编辑态
        if isOCREditingMode && !isForTranslation {
            isOCREditingMode = false
            return
        }

        isOCRLoading = true

        var targetImage: CGImage?
        if annotations.isEmpty {
            targetImage = image
        } else {
            let exportView = AnnotationCanvasLayer(
                image: image,
                displaySize: originalSize,
                annotations: annotations,
                currentAnnotation: nil
            )
            let renderer = ImageRenderer(content: exportView)
            renderer.scale = 1.0
            targetImage = renderer.cgImage
        }

        guard let finalImage = targetImage else {
            isOCRLoading = false
            return
        }

        TextRecognitionService.shared.recognizeTextWithBoundingBoxes(from: finalImage) { blocks, error in
            isOCRLoading = false
            let result = blocks?.map(\.text).joined(separator: "\n") ?? ""

            if result.isEmpty {
                print("⚠️ [OCR] 未识别到文字或发生错误: \(String(describing: error))")
                self.ocrResultText = "未识别到文字"
            } else {
                self.ocrResultText = result
            }

            self.ocrTextBlocks = blocks ?? []

            if isForTranslation {
                self.performTranslation()
            } else {
                // 进入图片上叠加可选择文本的 OCR 编辑态，同时保留侧边栏
                self.showOCRPanel = true
                self.isOCREditingMode = true
            }
        }
    }

    private func performTranslation() {
        guard !ocrResultText.isEmpty, ocrResultText != "未识别到文字" else {
            print("⚠️ [Translation] 没有可翻译的文本")
            return
        }

        withAnimation {
            showTranslationSidebar = true
        }

        guard #available(macOS 15.0, *) else {
            translatedText = "翻译功能需要 macOS 15 或更高版本"
            return
        }

        isTranslating = true
        translationConfiguration = TranslationSession.Configuration()
    }

    @ViewBuilder
    private var toolbarLayer: some View {
        UnifiedToolbarView(
            selectedTool: selectedToolBinding,
            selectedColor: $selectedColor,
            selectedFontSize: $selectedFontSize,
            selectedLineWidth: $selectedLineWidth,
            selectedBrushSize: $selectedBrushSize,
            selectedTextStyle: $selectedTextStyle,
            hasUndo: !undoStack.isEmpty,
            hasRedo: !redoStack.isEmpty,
            hasSelection: selectedAnnotationId != nil,
            isTextSelected: {
                guard let type = annotations.first(where: { $0.id == selectedAnnotationId })?.type else { return false }
                return type == .text || type == .numberedText || type == .rectText
            }(),
            onUndo: undo,
            onRedo: redo,
            onDelete: deleteSelectedAnnotation,
            onPin: pinScreenshot,
            onOCR: { performOCR(isForTranslation: false) },
            onTranslate: { performOCR(isForTranslation: true) },
            onCancel: onClose,
            onConfirm: exportAndClose,
            onGenerateDragURL: { return generateDragURL() },
            isEditingText: editingTextId != nil || editingCounterId != nil,
            aiMarkerCount: annotations.filter({ $0.type == .aiMarker }).count,
            onExportImage: { exportToAI(copyCoords: false) },
            onExportCoords: { exportToAI(copyCoords: true) }
        )
    }
}

/// 将需要渲染的层单独抽离出来
struct AnnotationCanvasLayer: View {
    let image: CGImage
    let displaySize: CGSize
    let annotations: [AnnotationItem]
    let currentAnnotation: AnnotationItem?
    var cornerRadius: CGFloat = 0

    // 编辑状态相关
    var selectedAnnotationId: UUID? = nil
    var editingTextId: UUID? = nil
    var editingCounterId: UUID? = nil
    var onTextChanged: ((UUID, String) -> Void)? = nil
    var onTextCommit: (() -> Void)? = nil
    var onCounterChanged: ((UUID, String) -> Void)? = nil
    var onSizeChanged: ((UUID, CGSize) -> Void)? = nil
    var clipRect: CGRect? = nil
    // 导出时已经通过 applyBrushEffects 把 blur/mosaic burn 到原图上，避免 SwiftUI 异步渲染丢失
    var skipBlurMosaic: Bool = false
    
    var body: some View {
        // 用于响应点击提交编辑态的透明背景，使用 contentShape 保证极低透明度下仍可命中
        let tapBackground = Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: displaySize.width, height: displaySize.height)
            .allowsHitTesting(true)
            .onTapGesture {
                onTextCommit?()
            }

        // 用于 mask 边界的占位视图，保留极微不透明度以避免 SwiftUI 视觉边界优化
        let maskPlaceholder = Color.white.opacity(0.0001)
            .frame(width: displaySize.width, height: displaySize.height)
        
        ZStack(alignment: .topLeading) {
            // 底图
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)

            // 将透明点击背景置于图片上方、标注下方，确保点击图片空白处可提交编辑态
            tapBackground

            // 将所有标注放在一个容器中以便统一裁切
            ZStack(alignment: .topLeading) {
                // 占位全屏，必须有一点不透明度，否则会被 SwiftUI 的 mask 视觉边界计算优化掉
                maskPlaceholder
                
                // 处理聚光灯 (Spotlight) 效果
                            let spotlights = (annotations + (currentAnnotation != nil ? [currentAnnotation!] : [])).filter { $0.type == .spotlight }
                            if !spotlights.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: displaySize.width, height: displaySize.height)
                        .mask(
                            ZStack {
                                Rectangle().fill(Color.white)
                                ForEach(spotlights) { spot in
                                    Rectangle()
                                        .fill(Color.black)
                                        .frame(width: spot.rect.width, height: spot.rect.height)
                                        .position(x: spot.rect.midX, y: spot.rect.midY)
                                }
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                        )
                }
                
                ForEach(annotations) { item in
                    Group {
                        // 导出时 blur/mosaic 已预处理到原图上，不再重复渲染
                        if skipBlurMosaic && (item.type == .blur || item.type == .mosaic) {
                            EmptyView()
                        } else {
                            AnnotationShapeView(
                                item: item,
                                isEditing: item.id == editingTextId,
                                isEditingCounter: item.id == editingCounterId,
                                isSelected: item.id == selectedAnnotationId,
                                onTextChanged: onTextChanged,
                                onTextCommit: onTextCommit,
                                onCounterChanged: onCounterChanged,
                                onSizeChanged: onSizeChanged,
                                baseImage: image,
                                displaySize: displaySize,
                                clipRect: clipRect // 传入
                            )
                        }

                        if item.id == selectedAnnotationId && item.type != .text && item.type != .numberedText && item.type != .rectText {
                            // 绘制 8 个控制柄 
                            ForEach(DragHandle.allCases, id: \.self) { handle in
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                                    .position(handlePosition(for: handle, rect: item.rect))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                
                if let current = currentAnnotation {
                    // 模糊/马赛克在绘制过程中直接渲染真实效果，让用户实时看到最终样式
                    if current.type == .blur || current.type == .mosaic,
                       let points = current.points, points.count > 1 {
                        BlurMosaicLiveView(
                            item: current,
                            baseImage: image,
                            displaySize: displaySize
                        )
                        .allowsHitTesting(false)
                    } else {
                        AnnotationShapeView(
                            item: current,
                            isEditing: false,
                            isEditingCounter: false,
                            isSelected: false,
                            onTextChanged: nil,
                            onTextCommit: nil,
                            onCounterChanged: nil,
                            onSizeChanged: nil,
                            baseImage: image,
                            displaySize: displaySize,
                            clipRect: clipRect // 传入
                        )
                    }
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            // 完全不裁切：Intel 上 clipShape 会导致矩形/椭圆/序号圆形等 Shape 透明；
            // 标注范围由 handleDragChange 中的坐标钳制保证
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// 仅在 rect 非 nil 时应用 clipShape，避免 Intel 上无意义的全屏 Path 裁切导致 Shape 透明。
    @ViewBuilder
    func clipIfNeeded(to rect: CGRect?) -> some View {
        if let rect = rect {
            self.clipShape(Path(rect))
        } else {
            self
        }
    }
}

/// 计算从矩形中心出发、穿过 `point` 的射线与矩形边框的交点。
/// 用于引线从矩形边框（而非内部或中心）精确连出。
private func rectBorderIntersection(rect: CGRect, through point: CGPoint) -> CGPoint {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let dx = point.x - center.x
    let dy = point.y - center.y
    if abs(dx) < 0.001 && abs(dy) < 0.001 { return center }

    var tX: CGFloat = .greatestFiniteMagnitude
    var tY: CGFloat = .greatestFiniteMagnitude

    if dx > 0 {
        tX = (rect.maxX - center.x) / dx
    } else if dx < 0 {
        tX = (rect.minX - center.x) / dx
    }

    if dy > 0 {
        tY = (rect.maxY - center.y) / dy
    } else if dy < 0 {
        tY = (rect.minY - center.y) / dy
    }

    let t = min(tX, tY)
    return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
}

func rectTextBounds(_ item: AnnotationItem) -> CGRect? {
    guard item.type == .rectText, let pts = item.points, pts.count >= 2 else { return nil }
    let minX = min(pts[0].x, pts[1].x)
    let maxX = max(pts[0].x, pts[1].x)
    let minY = min(pts[0].y, pts[1].y)
    let maxY = max(pts[0].y, pts[1].y)
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// 用逐块平均色算法生成马赛克（与微信截图专利 CN105787874B 一致）。
/// 对每个 blockSize×blockSize 区域计算 RGB 平均值，用平均色填充整个块。
/// 使用原图 colorSpace，避免 premultipliedLast/First 不兼容导致颜色错误。
func createMosaicCGImage(_ image: CGImage, blockSize: Int = 8) -> CGImage? {
    let w = image.width
    let h = image.height
    guard w > 0, h > 0, blockSize > 0 else { return nil }

    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    // 使用 premultipliedFirst + byteOrder32Little，macOS 最标准格式，兼容所有 CGImage
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    let bytesPerRow = w * 4

    guard let context = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                   space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    guard let dataPtr = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

    // 逐块计算平均色并填充（专利权利要求 4：average-color-per-block）
    for blockY in stride(from: 0, to: h, by: blockSize) {
        for blockX in stride(from: 0, to: w, by: blockSize) {
            let bw = min(blockSize, w - blockX)
            let bh = min(blockSize, h - blockY)

            var r: Int = 0, g: Int = 0, b: Int = 0, a: Int = 0, count: Int = 0

            for py in 0..<bh {
                for px in 0..<bw {
                    let idx = ((blockY + py) * w + (blockX + px)) * 4
                    // premultipliedFirst + byteOrder32Little: [BGRA] in memory
                    b += Int(dataPtr[idx])
                    g += Int(dataPtr[idx + 1])
                    r += Int(dataPtr[idx + 2])
                    a += Int(dataPtr[idx + 3])
                    count += 1
                }
            }

            let avgB = UInt8(b / count)
            let avgG = UInt8(g / count)
            let avgR = UInt8(r / count)
            let avgA = UInt8(a / count)

            // 用平均色填充整个块
            for py in 0..<bh {
                for px in 0..<bw {
                    let idx = ((blockY + py) * w + (blockX + px)) * 4
                    dataPtr[idx] = avgB
                    dataPtr[idx + 1] = avgG
                    dataPtr[idx + 2] = avgR
                    dataPtr[idx + 3] = avgA
                }
            }
        }
    }

    return context.makeImage()
}

/// 模糊/马赛克实时渲染视图（绘制过程中使用）
/// 采用 Photoshop 式预计算模式：onAppear 时对全图做一次效果处理，
/// 绘制时只更新笔触 mask，实现真正的实时交互。
/// 使用静态缓存避免实例重建时重新预计算（消除完成后闪烁）。
struct BlurMosaicLiveView: View {
    let item: AnnotationItem
    let baseImage: CGImage?
    let displaySize: CGSize?

    /// 预计算的全图效果图（模糊或马赛克版）
    @State private var effectImage: NSImage?

    private static let ciContext = CIContext()
    /// 缓存：key = "width x height - effectType"，value = 预计算效果图
    /// 同一张截图的 blur/mosaic 效果相同，所有实例共享缓存
    private static var effectCache: [String: NSImage] = [:]

    /// 清除缓存（新截图会话开始时调用）
    static func clearEffectCache() {
        effectCache.removeAll()
    }

    private static func cacheKey(for image: CGImage, type: AnnotationToolType) -> String {
        return "\(image.width)x\(image.height)-\(type)"
    }

    var body: some View {
        Group {
            if let effectImg = effectImage, let size = displaySize {
                if let points = item.points, points.count > 1 {
                    // 预计算完成：用笔触路径做 mask，实时显示效果
                    Image(nsImage: effectImg)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .mask(
                            Canvas { context, _ in
                                var path = Path()
                                path.move(to: points.first!)
                                path.addLines(points)
                                context.stroke(path, with: .color(.black),
                                    style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                            }
                        )
                        .allowsHitTesting(false)
                }
            } else {
                // 预计算未完成时显示轻量预览线
                if let points = item.points, points.count > 1, let size = displaySize {
                    let isBlur = item.type == .blur
                    Canvas { context, _ in
                        var path = Path()
                        path.move(to: points.first!)
                        path.addLines(points)
                        let previewColor: Color = isBlur ? Color.blue.opacity(0.3) : Color.gray.opacity(0.5)
                        context.stroke(path, with: .color(previewColor),
                            style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                }
            }
        }
        .id("blur-mosaic-live-\(item.id)")
        .onAppear {
            precomputeEffect()
        }
    }

    /// 对全图做一次效果处理，后续绘制只需更新 mask
    private func precomputeEffect() {
        guard let cgImage = baseImage, let size = displaySize, effectImage == nil else { return }

        let effectType = item.type
        let key = Self.cacheKey(for: cgImage, type: effectType)

        // 1. 先查缓存：如果同一张图已预计算过，直接使用（消除实例重建闪烁）
        if let cached = Self.effectCache[key] {
            self.effectImage = cached
            return
        }

        // 2. 缓存未命中：异步预计算
        DispatchQueue.global(qos: .userInitiated).async {
            var resultCGImage: CGImage?

            if effectType == .blur {
                // 高斯模糊全图，半径固定 8px（图像像素空间）
                let ciImage = CIImage(cgImage: cgImage)
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = ciImage.clampedToExtent()
                filter.radius = 8
                resultCGImage = filter.outputImage.flatMap { out in
                    Self.ciContext.createCGImage(out, from: ciImage.extent)
                }
            } else if effectType == .mosaic {
                // CoreGraphics 双向采样，产生均匀方块
                resultCGImage = createMosaicCGImage(cgImage, blockSize: 8)
            }

            if let result = resultCGImage {
                let nsImage = NSImage(cgImage: result, size: size)
                DispatchQueue.main.async {
                    // 存入缓存供其他实例使用
                    Self.effectCache[key] = nsImage
                    self.effectImage = nsImage
                }
            }
        }
    }
}

/// 单个标注形状渲染
struct AnnotationShapeView: View {
    let item: AnnotationItem
    let isEditing: Bool
    let isEditingCounter: Bool
    var isSelected: Bool = false
    let onTextChanged: ((UUID, String) -> Void)?
    let onTextCommit: (() -> Void)?
    var onCounterChanged: ((UUID, String) -> Void)? = nil
    var onSizeChanged: ((UUID, CGSize) -> Void)? = nil
    
    var baseImage: CGImage? = nil
    var displaySize: CGSize? = nil
    var clipRect: CGRect? = nil // 新增
    
    // Focus is now managed purely by AppKit to prevent SwiftUI from stealing it

    
    var body: some View {
        ZStack {
            switch item.type {
            case .rectangle:
                Rectangle()
                    .stroke(item.color, lineWidth: item.lineWidth)
                    .frame(width: item.rect.width, height: item.rect.height)
                    .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .filledRectangle:
                Rectangle()
                    .fill(item.color)
                    .frame(width: item.rect.width, height: item.rect.height)
                    .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .ellipse:
                Ellipse()
                    .stroke(item.color, lineWidth: item.lineWidth)
                    .frame(width: item.rect.width, height: item.rect.height)
                    .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .line:
                Canvas { context, size in
                    var path = Path()
                    path.move(to: item.startPoint)
                    path.addLine(to: item.endPoint)
                    context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth))
                }
                .id("line-\(item.color)-\(item.lineWidth)-\(item.startPoint)-\(item.endPoint)")
                
            case .arrow:
                ArrowView(start: item.startPoint, end: item.endPoint, color: item.color, lineWidth: item.lineWidth)
                    .id("arrow-\(item.color)-\(item.lineWidth)-\(item.startPoint)-\(item.endPoint)")
                    
            case .pencil:
                if let points = item.points, points.count > 1 {
                    // 局部渲染：只绘制笔触包围盒，降低 Intel 全屏重绘压力
                    let bounds = item.rect
                    let localPoints = points.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: localPoints.first!)
                        path.addLines(localPoints)
                        context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                    .id("pencil-\(item.id)")
                    .frame(width: bounds.width, height: bounds.height)
                    .offset(x: bounds.minX, y: bounds.minY)
                }

            case .highlighter:
                if let points = item.points, points.count > 1 {
                    let bounds = item.rect
                    let localPoints = points.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: localPoints.first!)
                        path.addLines(localPoints)
                        context.stroke(path, with: .color(item.color.opacity(0.5)), style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                    .id("highlighter-\(item.id)")
                    .frame(width: bounds.width, height: bounds.height)
                    .offset(x: bounds.minX, y: bounds.minY)
                }
                    
            case .text, .numberedText, .rectText:
                let fontSize = item.fontSize ?? 16.0
                let fontStyle = item.fontStyle ?? .standard
                
                let rightEdge = clipRect?.maxX ?? displaySize?.width ?? 800
                let numberOffset = (item.type == .numberedText) ? (fontSize * 1.5 + 8) : 0
                // 获取计算宽度：rectText 的文本框起点是 startPoint + calloutOffset
                let textOriginX = item.type == .rectText
                    ? item.startPoint.x + (item.calloutOffset?.width ?? 0)
                    : item.startPoint.x + numberOffset
                let limitWidth = rightEdge - textOriginX - 20
                // 如果有自定义定宽，则使用定宽；否则使用最终边界限制宽度
                let finalMaxWidth = item.customWidth ?? max(50, limitWidth)
                
                ZStack(alignment: .topLeading) {
                    // 矩形框文本：拖拽过程中只画矩形框，等 calloutOffset 设置完成后再显示文本框与引线
                    if item.type == .rectText, let rectBounds = rectTextBounds(item), rectBounds.width > 1, rectBounds.height > 1 {
                        let rectLineWidth = max(2, fontSize * 0.15)

                        // 引线：从矩形边框最近点连到文本框边缘，矩形填充覆盖根部，保证平滑且无缝隙
                        if let offset = item.calloutOffset {
                            let textOrigin = CGPoint(x: item.startPoint.x + offset.width, y: item.startPoint.y + offset.height)
                            let textW = max(item.endPoint.x - textOrigin.x, 20)
                            let textH = max(item.endPoint.y - textOrigin.y, 20)
                            let textBounds = CGRect(origin: textOrigin, size: CGSize(width: textW, height: textH))
                            let textCenter = CGPoint(x: textBounds.midX, y: textBounds.midY)

                            // 引线起点：矩形边框与“矩形中心 → 文本中心”射线的交点，
                            // 并沿外法向偏移半线宽，确保与矩形外边框精确相接
                            let rectCenter = CGPoint(x: rectBounds.midX, y: rectBounds.midY)
                            let innerStart = rectBorderIntersection(rect: rectBounds, through: textCenter)
                            let dxToText = textCenter.x - rectCenter.x
                            let dyToText = textCenter.y - rectCenter.y
                            let distanceToText = sqrt(dxToText * dxToText + dyToText * dyToText)
                            let halfStroke = rectLineWidth / 2
                            let start: CGPoint = distanceToText > 0 ? CGPoint(
                                x: innerStart.x + (dxToText / distanceToText) * halfStroke,
                                y: innerStart.y + (dyToText / distanceToText) * halfStroke
                            ) : innerStart

                            // 引线终点：文本框边框与“文本中心 → 矩形边框点”射线的交点，
                            // 并向文本框中心内缩 4pt，让引线真正插入文本框背景下方，消除缝隙
                            let innerEnd = rectBorderIntersection(rect: textBounds, through: innerStart)
                            let dxToRect = innerStart.x - innerEnd.x
                            let dyToRect = innerStart.y - innerEnd.y
                            let distanceToRect = sqrt(dxToRect * dxToRect + dyToRect * dyToRect)
                            // 向文本框内部内缩，确保引线端点被文本框背景覆盖，无可见缝隙
                            let overlap: CGFloat = 4.0
                            let end: CGPoint = distanceToRect > 0 ? CGPoint(
                                x: innerEnd.x - (dxToRect / distanceToRect) * overlap,
                                y: innerEnd.y - (dyToRect / distanceToRect) * overlap
                            ) : innerEnd

                            // 根据主方向选择 S 曲线方向（水平或垂直），使引线自然贴合相对位置
                            let isHorizontal = abs(end.x - start.x) >= abs(end.y - start.y)
                            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                            let control1 = isHorizontal
                                ? CGPoint(x: mid.x, y: start.y)
                                : CGPoint(x: start.x, y: mid.y)
                            let control2 = isHorizontal
                                ? CGPoint(x: mid.x, y: end.y)
                                : CGPoint(x: end.x, y: mid.y)

                            Canvas { context, size in
                                var path = Path()
                                path.move(to: start)
                                path.addCurve(to: end, control1: control1, control2: control2)
                                context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: rectLineWidth, lineCap: .round, lineJoin: .round))
                            }
                            .allowsHitTesting(false)
                        }

                        // 矩形框：内部透明，只保留边框，避免遮挡底层图像
                        Rectangle()
                            .fill(Color.clear)
                            .overlay(
                                Rectangle()
                                    .stroke(item.color, lineWidth: rectLineWidth)
                            )
                            .frame(width: rectBounds.width, height: rectBounds.height)
                            .position(x: rectBounds.midX, y: rectBounds.midY)
                    }
                    
                    if item.type == .numberedText {
                        let countStr = item.displayCounterString
                        let offset = item.calloutOffset ?? CGSize(width: 16.0, height: -45.0)
                        
                        // 连接线 (从 startPoint 到 text box)
                        Canvas { context, size in
                            var path = Path()
                            path.move(to: item.startPoint)
                            
                            // textOrigin is the TOP-LEFT corner of the text box
                            let textOrigin = CGPoint(x: item.startPoint.x + offset.width, y: item.startPoint.y + offset.height)
                            let textWidth = max(item.rect.width, 20) // Ensure a minimum width to prevent early zero-width gaps
                            let textHeight = max(item.rect.height, 20)
                            let textCenterY = textOrigin.y + textHeight / 2
                            
                            // line connects to left or right edge depending on relative position
                            let isLeft = offset.width < 0
                            // Slightly overlap the text box edge to prevent gaps (using +/- 2px)
                            let textAnchorX = isLeft ? (textOrigin.x + textWidth - 2.0) : (textOrigin.x + 2.0)
                            
                            let start = item.startPoint
                            let end = CGPoint(x: textAnchorX, y: textCenterY)
                            
                            // Smooth Bezier Curve (S-Curve)
                            let controlPointX = (start.x + end.x) / 2
                            let control1 = CGPoint(x: controlPointX, y: start.y)
                            let control2 = CGPoint(x: controlPointX, y: end.y)
                            
                            path.addCurve(to: end, control1: control1, control2: control2)
                            
                            let strokeStyle = StrokeStyle(
                                lineWidth: max(2, fontSize * 0.15),
                                lineCap: .round,
                                lineJoin: .round
                            )
                            context.stroke(path, with: .color(item.color), style: strokeStyle)
                        }
                        .allowsHitTesting(false)
                        
                        // 序号点 (使用标准 SwiftUI 形状)
                        let isEditingCounterState = isEditingCounter && item.type == .numberedText
                        ZStack {
                            Circle().fill(item.color).frame(width: fontSize * 1.5, height: fontSize * 1.5)
                            if isEditingCounterState {
                                AnyView(AutoSizingTextView(
                                text: Binding(
                                    get: { item.customCounterString ?? (item.counterValue != nil ? String(item.counterValue!) : "1") },
                                    set: { onCounterChanged?(item.id, $0) }
                                ),
                                fontSize: fontSize * 0.8,
                                textColor: item.color == .white ? .black : .white,
                                customWidth: fontSize * 1.5,
                                maxWidth: fontSize * 2.0,
                                isEditable: true,
                                placeholder: nil,
                                commitOnReturn: true,
                                onCommit: { onTextCommit?() }
                            )
                            .frame(width: fontSize * 1.5, height: fontSize * 1.5))
                            } else {
                                AnyView(Text(countStr)
                                    .font(.system(size: fontSize * 0.8, weight: .bold))
                                    .foregroundColor(item.color == .white ? .black : .white))
                            }
                        }
                        .frame(width: fontSize * 1.5, height: fontSize * 1.5)
                        .position(x: item.startPoint.x, y: item.startPoint.y)
                        .contentShape(Circle())
                        .onTapGesture(count: 2) {
                            NotificationCenter.default.post(name: NSNotification.Name("CounterDoubleTapped"), object: item.id)
                        }
                    }
                    
                    let getContrastColor: (Color) -> Color = { bg in
                        // boxed 文本：白色背景用黑字，其他颜色背景统一用白字
                        let nsColor = NSColor(bg).usingColorSpace(.sRGB) ?? NSColor(bg)
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                        nsColor.getRed(&r, green: &g, blue: &b, alpha: nil)
                        let isWhite = r > 0.95 && g > 0.95 && b > 0.95
                        return isWhite ? .black : .white
                    }
                    
                    let textColor = fontStyle == .outlined ? .white : (fontStyle == .standard ? item.color : getContrastColor(item.color))
                    let textPadding: CGFloat = (fontStyle == .boxed || fontStyle == .roundedBoxed) ? 0.0 : 0.0
                    let cornerRad: CGFloat = fontStyle == .roundedBoxed ? 12.0 : 4.0
                    let bgColor = (fontStyle == .boxed || fontStyle == .roundedBoxed) ? item.color.opacity(0.85) : Color.clear
                    
                    // 统一的文本区渲染逻辑 (TextField 和展示态) - 用于 .text / .numberedText / 已完成的 rectText
                    if item.type != .rectText || item.calloutOffset != nil {
                    Group {
                        ZStack(alignment: .topLeading) {
                            Group {
                                if isEditing {
                                    AnyView(AutoSizingTextView(
                                        text: Binding(
                                            get: { item.text ?? "" },
                                            set: { onTextChanged?(item.id, $0) }
                                        ),
                                        fontSize: fontSize,
                                        textColor: textColor,
                                        customWidth: item.customWidth != nil ? max(item.customWidth! - 12 - textPadding * 2, 10) : nil,
                                        maxWidth: max(finalMaxWidth - 12 - textPadding * 2, 10),
                                        isEditable: isEditing,
                                        placeholder: isEditing ? "输入文本..." : nil,
                                        onCommit: { onTextCommit?() }
                                    ))
                                } else {
                                    AnyView(Text(item.text ?? "")
                                        .font(.system(size: fontSize, weight: .semibold))
                                        .foregroundColor(textColor)
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: item.customWidth != nil ? max(item.customWidth! - 12 - textPadding * 2, 10) : nil, alignment: .leading))
                                }
                            }
                            .shadow(color: fontStyle == .outlined && !isEditing ? item.color : .clear, radius: 1, x: 1, y: 1)
                            .shadow(color: fontStyle == .outlined && !isEditing ? item.color : .clear, radius: 1, x: -1, y: -1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .padding(textPadding)
                            .fixedSize(horizontal: item.customWidth == nil, vertical: true)
                            .allowsHitTesting(isEditing)
                        }
                    }
                    .frame(width: item.customWidth, alignment: .leading)
                    .background(bgColor)
                    .cornerRadius(cornerRad)
                    .overlay(
                        Group {
                            if isSelected && !isEditing {
                                RoundedRectangle(cornerRadius: cornerRad)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                    .padding(-1)
                            } else if isEditing && fontStyle == .standard {
                                RoundedRectangle(cornerRadius: cornerRad)
                                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            }
                            
                            if isSelected {
                                GeometryReader { geo in
                                    let rect = CGRect(origin: .zero, size: geo.size)
                                    // 8 个控制柄 (内嵌到视图层，绝对无延迟)
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
                        }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    onSizeChanged?(item.id, geo.size)
                                }
                                .onChange(of: geo.size) { newSize in
                                    onSizeChanged?(item.id, newSize)
                                }
                        }
                    )
                    .offset(
                        x: (item.type == .numberedText || item.type == .rectText) ? item.startPoint.x + (item.calloutOffset?.width ?? (item.type == .rectText ? 0 : 16.0)) : item.startPoint.x,
                        y: (item.type == .numberedText || item.type == .rectText) ? item.startPoint.y + (item.calloutOffset?.height ?? (item.type == .rectText ? 0 : -45.0)) : item.startPoint.y
                    )
                    // 扩大双击热区
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            // 由于双击检测由外层托管比较难以命中，直接在视图层处理
                            NotificationCenter.default.post(name: NSNotification.Name("AnnotationDoubleTapped"), object: item.id)
                        }
                    )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    
            case .blur, .mosaic:
                // 使用与实时绘制相同的预计算全图效果 + mask 方式，
                // 确保完成后效果与实时绘制完全一致（网格对齐、色块均匀）。
                BlurMosaicLiveView(
                    item: item,
                    baseImage: baseImage,
                    displaySize: displaySize
                )
            
            case .aiMarker:
                // 半透明紫色和虚线细边框
                ZStack {
                    Rectangle()
                        .fill(TMDesign.Colors.purple.opacity(0.15))
                    Rectangle()
                        .stroke(TMDesign.Colors.purple.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                .frame(width: item.rect.width, height: item.rect.height)
                .overlay(
                    // 左上角的编号圈
                    ZStack {
                        Circle()
                            .fill(TMDesign.Colors.purple.opacity(0.8))
                            .frame(width: 20, height: 20)
                        Text(item.displayCounterString)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .position(x: 0, y: 0),
                    alignment: .topLeading
                )
                .position(x: item.rect.midX, y: item.rect.midY)
            
            case .spotlight:
                Color.clear
                    .frame(width: item.rect.width, height: item.rect.height)
                    
            case .counter:
                let size = item.fontSize ?? 16.0
                let isEditingCounterState = isEditingCounter && item.type == .counter
                ZStack {
                    Canvas { context, sz in
                        context.fill(Path(ellipseIn: CGRect(origin: .zero, size: sz)), with: .color(item.color))
                    }
                    .frame(width: size * 1.5, height: size * 1.5)
                    
                    if isEditingCounterState {
                        AnyView(AutoSizingTextView(
                            text: Binding(
                                get: { item.customCounterString ?? (item.counterValue != nil ? String(item.counterValue!) : "1") },
                                set: { onCounterChanged?(item.id, $0) }
                            ),
                            fontSize: size * 0.8,
                            textColor: item.color == .white ? .black : .white,
                            customWidth: size * 1.5,
                            maxWidth: size * 2.0,
                            isEditable: true,
                            placeholder: nil,
                            commitOnReturn: true,
                            onCommit: { onTextCommit?() }
                        )
                        .frame(width: size * 1.5, height: size * 1.5))
                    } else {
                        AnyView(Text(item.displayCounterString)
                            .font(.system(size: size * 0.8, weight: .bold))
                            .foregroundColor(item.color == .white ? .black : .white))
                    }
                }
                .frame(width: size * 1.5, height: size * 1.5)
                .position(x: item.endPoint.x, y: item.endPoint.y)
                .contentShape(Circle())
                .onTapGesture(count: 2) {
                    NotificationCenter.default.post(name: NSNotification.Name("CounterDoubleTapped"), object: item.id)
                }
        }
    }
}
}

struct ArrowView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    
    var body: some View {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        if length == 0 {
            Color.clear
        } else {
            let angle = atan2(dy, dx)
            let headLength = min(max(12.0, lineWidth * 3.5), length * 0.6)
            let arrowAngle: CGFloat = .pi / 6
            
            // Base of the head
            let baseLength = headLength * cos(arrowAngle)
            let shaftEnd = CGPoint(
                x: end.x - baseLength * cos(angle),
                y: end.y - baseLength * sin(angle)
            )
            
            let p1 = CGPoint(
                x: end.x - headLength * cos(angle - arrowAngle),
                y: end.y - headLength * sin(angle - arrowAngle)
            )
            let p2 = CGPoint(
                x: end.x - headLength * cos(angle + arrowAngle),
                y: end.y - headLength * sin(angle + arrowAngle)
            )
            
            Canvas { context, size in
                // Shaft
                var shaft = Path()
                shaft.move(to: start)
                shaft.addLine(to: shaftEnd)
                context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                
                // Head (filled triangle)
                var head = Path()
                head.move(to: end)
                head.addLine(to: p1)
                head.addLine(to: p2)
                head.closeSubpath()
                context.fill(head, with: .color(color))
            }
        }
    }
    
}

/// 工具按钮组件
struct ToolButton: View {
    let tool: AnnotationToolType
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var iconName: String {
        switch tool {
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "t.square"
        case .numberedText: return "text.badge.star"
        case .rectText: return sfSymbol("bubble.and.pencil", fallback: "text.bubble")
        case .counter: return "1.circle"
        case .pencil: return "paintbrush.pointed"
        case .highlighter: return "marker.fill"
        case .blur: return "drop"
        case .mosaic: return "square.grid.3x3.topleft.filled"
        case .spotlight: return "theatermasks"
        case .aiMarker: return "location.fill.viewfinder"
        }
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
    
    var body: some View {
        Button(action: action) {
            Group {
                if isCustomSVG {
                    SVGIconView(pathData: customSVGPath, color: isSelected ? .white : .primary)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                }
            }
            .frame(width: 32, height: 32)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(LanguageManager.shared.localizedString(forKey: tool.rawValue))
    }
}

struct TitleBarDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TitleDragNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class TitleDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            self.window?.zoom(nil)
            return
        }
        self.window?.performDrag(with: event)
    }
}

// MARK: - AutoSizingTextView

struct AutoSizingTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: Color
    var customWidth: CGFloat?
    var maxWidth: CGFloat
    var isEditable: Bool
    var placeholder: String?
    var commitOnReturn: Bool = false
    var onCommit: () -> Void
    
    func makeNSView(context: Context) -> AutoResizingNSTextView {
        let textView = AutoResizingNSTextView()
        textView.wantsLayer = true
        textView.layer?.backgroundColor = NSColor.clear.cgColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        
        let nsColor = NSColor(textColor).usingColorSpace(.sRGB) ?? NSColor(textColor)
        textView.textColor = nsColor
        
        textView.delegate = context.coordinator
        
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.focusRingType = .none
        textView.drawsBackground = false
        
        // Only focus if editable
        if isEditable {
            textView.isEditable = true
            textView.isSelectable = true
            
            // Prevent greedy expansion in SwiftUI
            textView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            // Auto-focus when created
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
            
            // 安装外部点击监听：点击文本视图外部时自动提交编辑
            context.coordinator.installOutsideClickMonitor(for: textView)
        } else {
            textView.isEditable = false
            textView.isSelectable = false
            
            textView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            context.coordinator.removeOutsideClickMonitor()
        }

        // 初始化 placeholder；refreshPlaceholder 统一刷新时机，避免多路径 needsDisplay 竞争
        if let placeholder = placeholder {
            textView.customPlaceholder = placeholder
            textView.refreshPlaceholder()
        }

        return textView
    }

    func updateNSView(_ nsView: AutoResizingNSTextView, context: Context) {
        // 当编辑态结束时，安全地辞去第一响应者，避免在 async 提交路径中访问已释放的 NSTextView
        if context.coordinator.wasEditable && !isEditable {
            nsView.window?.makeFirstResponder(nil)
        }
        context.coordinator.wasEditable = isEditable

        nsView.isEditable = isEditable
        nsView.isSelectable = isEditable
        // 保持透明背景，避免 placeholder 被系统背景覆盖
        nsView.drawsBackground = false
        nsView.backgroundColor = .clear

        if isEditable {
            context.coordinator.installOutsideClickMonitor(for: nsView)
        } else {
            context.coordinator.removeOutsideClickMonitor()
        }
        if nsView.string != text {
            nsView.string = text
            nsView.invalidateIntrinsicContentSize()
        }

        // 仅在值变化时更新 font/textColor，减少不必要刷新
        let newFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        if nsView.font != newFont {
            nsView.font = newFont
        }
        let nsColor = NSColor(textColor).usingColorSpace(.sRGB) ?? NSColor(textColor)
        if nsView.textColor != nsColor {
            nsView.textColor = nsColor
        }

        // 仅在变化时更新 placeholder
        let newPlaceholder = placeholder
        if nsView.customPlaceholder != newPlaceholder {
            nsView.customPlaceholder = newPlaceholder
        }

        if let cw = customWidth {
            nsView.isHorizontallyResizable = false
            nsView.textContainer?.widthTracksTextView = true
            // Account for padding by providing exact container size if needed, but we do padding in SwiftUI.
            nsView.textContainer?.containerSize = NSSize(width: cw, height: CGFloat.greatestFiniteMagnitude)
            nsView.frame.size.width = cw
        } else {
            nsView.isHorizontallyResizable = true
            nsView.textContainer?.widthTracksTextView = false
            nsView.textContainer?.containerSize = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        // Force layout update so intrinsicContentSize is accurate immediately
        nsView.invalidateIntrinsicContentSize()
        // 统一刷新 placeholder，避免在多个 override 方法中重复 needsDisplay
        nsView.refreshPlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ nsView: AutoResizingNSTextView, coordinator: Coordinator) {
        coordinator.removeOutsideClickMonitor()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextView
        private var outsideClickMonitor: Any?
        fileprivate var wasEditable: Bool = false

        init(_ parent: AutoSizingTextView) {
            self.parent = parent
        }

        /// 安装本地鼠标监听：点击文本视图外部时发送提交通知，
        /// 由 AnnotationRootView / OverlayRootView 统一响应，避免 closure 直接捕获 View 实例导致闪崩。
        func installOutsideClickMonitor(for textView: AutoResizingNSTextView) {
            removeOutsideClickMonitor()
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak textView] event in
                guard let textView = textView, textView.isEditable else { return event }
                guard let window = textView.window else { return event }
                let locationInWindow = event.locationInWindow
                let locationInView = textView.convert(locationInWindow, from: nil)
                if !textView.bounds.contains(locationInView), window.firstResponder === textView {
                    // 异步发送通知，避免在 NSEvent 处理路径内同步修改 SwiftUI 状态
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: commitTextEditNotification, object: nil)
                    }
                }
                return event
            }
        }

        func removeOutsideClickMonitor() {
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AutoResizingNSTextView else { return }
            self.parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 单行编辑场景（如序号编辑）按回车异步发送提交通知，由视图统一处理排序。
            if parent.commitOnReturn, commandSelector == #selector(NSResponder.insertNewline(_:)) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: commitTextEditNotification, object: nil)
                }
                return true
            }
            return false
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? AutoResizingNSTextView else { return }
            // 仅当文本视图仍持有编辑态标识时触发提交，避免重复调用。
            // 通过通知机制由 AnnotationRootView 统一处理，避免 closure 捕获过期 View 实例导致闪崩。
            if textView.isEditable {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: commitTextEditNotification, object: nil)
                }
            }
        }
    }
}

class AutoResizingNSTextView: NSTextView {
    /// 自定义 placeholder 文字
    var customPlaceholder: String?

    private func placeholderColor() -> NSColor {
        (self.textColor ?? NSColor.gray).withAlphaComponent(0.5)
    }

    private var shouldShowPlaceholder: Bool {
        string.isEmpty && customPlaceholder != nil
    }

    private func drawPlaceholder() {
        guard shouldShowPlaceholder, let placeholder = customPlaceholder else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: self.font ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: placeholderColor()
        ]
        placeholder.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs)
    }

    override func resetCursorRects() {
        if self.isSelectable {
            super.resetCursorRects()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)

        // When there is a placeholder and no text, we still need to provide enough width
        // for the placeholder so it isn't clipped
        var width = max(ceil(rect.width) + 2, 2)
        let height = max(ceil(rect.height), 10)

        if shouldShowPlaceholder, let placeholder = customPlaceholder {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.font ?? NSFont.systemFont(ofSize: 16)
            ]
            let pSize = placeholder.size(withAttributes: attrs)
            width = max(width, pSize.width + 2)
        }

        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 确保 super.draw 在透明背景下进行，placeholder 在其后绘制
        super.draw(dirtyRect)
        drawPlaceholder()
    }

    /// 在文本变化、焦点切换、尺寸变化后统一刷新 placeholder，避免多路径重复 needsDisplay
    func refreshPlaceholder() {
        self.needsDisplay = true
    }
}

struct BrushCursorView: View {
    let selectedTool: AnnotationToolType
    let selectedLineWidth: CGFloat
    let scale: CGFloat
    
    var brushSize: CGFloat {
        let lw = max(1.0, selectedLineWidth / 4.0)
        let baseSize: CGFloat = (selectedTool == .pencil) ? lw : max(20.0, lw * 2.0)
        return baseSize * scale
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
            Circle()
                .stroke(Color.black, lineWidth: 1.5)
            Circle()
                .stroke(Color.white, lineWidth: 0.8)
        }
        .frame(width: brushSize, height: brushSize)
        .allowsHitTesting(false)
    }
}
