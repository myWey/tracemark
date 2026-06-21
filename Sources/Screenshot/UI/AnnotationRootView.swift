import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import Translation


/// 标注画布视图
public struct AnnotationRootView: View {
    let image: CGImage
    let originalSize: CGSize
    @State private var recordId: UUID?
    let onClose: () -> Void

    @StateObject private var editModel: AnnotationEditViewModel

    @State private var selectedOCRBlockId: UUID? = nil
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    /// 工具切换的自定义 Binding：切换工具前通过通知异步提交编辑态，
    /// 避免 closure 直接捕获 AnnotationRootView 实例方法导致闪崩。
    private var selectedToolBinding: Binding<AnnotationToolType> {
        Binding(
            get: { editModel.selectedTool },
            set: { newTool in
                guard newTool != editModel.selectedTool else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .commitTextEdit, object: nil)
                }
                editModel.selectedTool = newTool
            }
        )
    }

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
        self._editModel = StateObject(wrappedValue: AnnotationEditViewModel(
            annotations: initialAnnotations,
            behavior: .annotationConfig,
            selectedTool: .aiMarker,
            hoverPoint: .zero
        ))
    }
    
    private func commitTextEdit() {
        if let currentEditing = editModel.editingTextId {
            if let idx = editModel.annotations.firstIndex(where: { $0.id == currentEditing }) {
                if (editModel.annotations[idx].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    editModel.annotations.remove(at: idx)
                } else {
                    let item = editModel.annotations[idx]
                    let fontSize = item.fontSize ?? 16.0
                    let singleLineHeight = fontSize * 1.2 + 16
                    if item.customWidth == nil,
                       (item.text ?? "").contains("\n") || item.rect.height > singleLineHeight + 4 {
                        editModel.annotations[idx].customWidth = item.rect.width
                    }
                }
            }
            editModel.editingTextId = nil
        }
        if let currentEditingCounter = editModel.editingCounterId {
            if let idx = editModel.annotations.firstIndex(where: { $0.id == currentEditingCounter }) {
                let newStr = editModel.annotations[idx].customCounterString ?? ""
                editModel.reorderCounters(after: currentEditingCounter, newString: newStr)
            }
            editModel.editingCounterId = nil
        }
    }

    /// 点击空白处提交所有编辑态（counter / text）
    private func commitAllEdits() {
        guard editModel.editingTextId != nil || editModel.editingCounterId != nil else { return }
        // 先处理数据与排序；编辑态 ID 清空后，AutoSizingTextView.updateNSView
        // 会检测到编辑态结束并安全地辞去 NSTextView 的第一响应者，
        // 避免在 async 通知路径中直接访问可能已释放的 responder。
        commitTextEdit()
    }

    private func deleteSelectedAnnotation() {
        guard let selectedId = editModel.selectedAnnotationId,
              let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        editModel.prepareForWrite()
        let deletedItem = editModel.annotations[index]
        editModel.annotations.remove(at: index)

        // 序号顺延算法 (Phase 2)
        if (deletedItem.type == .counter || deletedItem.type == .numberedText),
           let deletedValue = deletedItem.counterValue {
            for i in 0..<editModel.annotations.count {
                if (editModel.annotations[i].type == .counter || editModel.annotations[i].type == .numberedText),
                   let val = editModel.annotations[i].counterValue, val > deletedValue {
                    editModel.annotations[i].counterValue = val - 1
                }
            }
        }

        editModel.selectedAnnotationId = nil
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
                                editModel.selectedAnnotationId = nil
                            }

                        // Canvas is exactly the visual size, placed at offset
                        AnnotationCanvasLayer(
                            image: image,
                            displaySize: originalSize,
                            annotations: editModel.annotations,
                            currentAnnotation: editModel.currentAnnotation,
                            selectedAnnotationId: editModel.selectedAnnotationId,
                            editingTextId: editModel.editingTextId,
                            editingCounterId: editModel.editingCounterId,
                            onTextChanged: { id, newText in
                                if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
                                    editModel.annotations[index].text = newText
                                }
                            },
                            onTextCommit: {
                                // 防止 textDidEndEditing 与点击空白导致的重复提交
                                if editModel.editingTextId != nil || editModel.editingCounterId != nil {
                                    commitAllEdits()
                                }
                            },

                            onCounterChanged: { id, str in
                                if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
                                    editModel.annotations[index].customCounterString = str
                                }
                            },
                            onSizeChanged: { id, size in
                                DispatchQueue.main.async {
                                    if let index = editModel.annotations.firstIndex(where: { $0.id == id }) {
                                        let item = editModel.annotations[index]
                                        let offset = item.calloutOffset ?? (item.type == .numberedText ? CGSize(width: 16.0, height: -45.0) : .zero)
                                        let endX = item.startPoint.x + offset.width + size.width
                                        let endY = item.startPoint.y + offset.height + size.height
                                        if item.endPoint.x != endX || item.endPoint.y != endY {
                                            editModel.annotations[index].endPoint = CGPoint(x: endX, y: endY)
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
                                        editModel.hoverPoint = pt
                                        editModel.isHoveringCanvas = true
                                        handleHover(mapPoint(pt))
                                    } else {
                                        editModel.isHoveringCanvas = false
                                        NSCursor.arrow.set()
                                    }
                                },
                                onHoverExited: {
                                    editModel.isHoveringCanvas = false
                                    NSCursor.arrow.set()
                                },
                                activeTool: editModel.selectedTool,
                                onUndo: editModel.undo,
                                onRedo: editModel.redo,
                                onDelete: deleteSelectedAnnotation,
                                annotations: editModel.annotations,
                                mapPoint: mapPoint
                            )
                            .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                            .allowsHitTesting(editModel.editingTextId == nil && editModel.editingCounterId == nil && !isOCREditingMode)
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
                        let isBrush = [AnnotationToolType.pencil, .highlighter, .blur, .mosaic].contains(editModel.selectedTool)
                        if editModel.isHoveringCanvas && isBrush {
                            BrushCursorView(
                                selectedTool: editModel.selectedTool,
                                selectedLineWidth: editModel.selectedLineWidth,
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
        .onReceive(NotificationCenter.default.publisher(for: .triggerPostCaptureAction)) { notification in
            if let action = notification.object as? PostCaptureAction {
                if action == .ocr {
                    performOCR(isForTranslation: false)
                } else if action == .translate {
                    performOCR(isForTranslation: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .counterDoubleTapped)) { notification in
            if let id = notification.object as? UUID {
                editModel.editingCounterId = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitTextEdit)) { _ in
            if editModel.editingTextId != nil || editModel.editingCounterId != nil {
                commitAllEdits()
            }
        }
        .onChange(of: editModel.selectedColor) { newColor in
            updateSelectedAnnotation(color: newColor)
        }
        .onChange(of: editModel.selectedFontSize) { newSize in
            updateSelectedAnnotation(fontSize: newSize)
        }
        .onChange(of: editModel.selectedLineWidth) { newSize in
            updateSelectedAnnotation(lineWidth: newSize)
        }
        .onChange(of: editModel.selectedTextStyle) { newStyle in
            updateSelectedAnnotation(style: newStyle)
        }
        .onChange(of: editModel.selectedAnnotationId) { newId in
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
                    AppLogger.ui.error("❌ [Translation] 翻译失败: \(String(describing: error))")
                    translatedText = "翻译失败：\(error.localizedDescription)"
                }
                isTranslating = false
            }
        } else {
            content
        }
    }

// MARK: - Interaction Handlers

    private func isPointInNumberedCircle(_ point: CGPoint, item: AnnotationItem) -> Bool {
        guard item.type == .numberedText else { return false }
        let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.renderSizeMultiplier
        let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
        return circleRect.contains(point)
    }

    private func hitTestAnnotation(point: CGPoint) -> (UUID, DragHandle?)? {
        // 检查是否点中了 NumberedText 的起始点圆圈
        if let selectedId = editModel.selectedAnnotationId,
           let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }) {
            let item = editModel.annotations[index]
            if item.type == .numberedText {
                let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.renderSizeMultiplier
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(point) {
                    return (selectedId, .calloutOrigin)
                }
            }
        }
        
        // 先检查是否点中了某个控制柄（文本框控制柄）
        if let selectedId = editModel.selectedAnnotationId,
           let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }) {
            let itemRect = editModel.annotations[index].rect
            let itemType = editModel.annotations[index].type
            let isText = itemType == .text || itemType == .numberedText || itemType == .rectText

            if let handle = AnnotationGeometry.hitTestHandle(point: point, in: itemRect, cornerMinHitZone: 10, edgeHitZone: nil) {
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
        if let selectedId = editModel.selectedAnnotationId,
           let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }),
           let rectBounds = rectTextBounds(editModel.annotations[index]),
           rectBounds.contains(point) {
            return (selectedId, .calloutOrigin)
        }

        // 检查未选中的 NumberedText 的起始点圆圈
        for item in editModel.annotations.reversed() {
            if item.type == .numberedText {
                let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.renderSizeMultiplier
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(point) {
                    return (item.id, .calloutOrigin)
                }
            }
        }

        // 检查未选中的 RectText 的矩形框
        for item in editModel.annotations.reversed() {
            if let rectBounds = rectTextBounds(item), rectBounds.contains(point) {
                return (item.id, .calloutOrigin)
            }
        }

        // 再检查是否点中了某个标注的包围盒（文本框或其他形状）
        for item in editModel.annotations.reversed() {
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
        editModel.dragStartClickCount = clickCount
        editModel.dragStartPos = point
        editModel.lastDragPoint = point
        let now = ProcessInfo.processInfo.systemUptime
        let clickInterval = now - editModel.lastClickTime
        editModel.lastClickTime = now
        
        if let (id, handle) = hitTestAnnotation(point: point) {
            // 如果点中其他元素，先统一提交当前编辑态
            if (editModel.editingTextId != nil && editModel.editingTextId != id) || (editModel.editingCounterId != nil && editModel.editingCounterId != id) {
                commitAllEdits()
            }

            editModel.prepareForWrite()
            editModel.selectedAnnotationId = id
            editModel.annotationActiveHandle = handle
            editModel.annotationInitialItem = editModel.annotations.first(where: { $0.id == id })
            editModel.annotationDragStartPoint = point
            
            // 双击进入编辑态：支持文本框、带序号文本、矩形框文本，以及双击序号圆圈。
            // 条件放宽：系统 clickCount 不可靠或用户双击稍慢时，用 editModel.lastClickAnnotationId + 0.5s 兜底。
            if clickCount >= 2 || (editModel.lastClickAnnotationId == id && clickInterval < InteractionConfig.annotationDoubleClickFallbackInterval) {
                let item = editModel.annotations.first(where: { $0.id == id })
                // 优先判断：如果命中带序号文本的序号圆圈，进入序号编辑（即使 hitTest 返回文本框）
                if let item = item, item.type == .numberedText, isPointInNumberedCircle(point, item: item) {
                    editModel.editingCounterId = id
                } else if item?.type == .text || item?.type == .numberedText || item?.type == .rectText {
                    editModel.editingTextId = id
                } else if item?.type == .counter {
                    editModel.editingCounterId = id
                }
            }
            editModel.lastClickAnnotationId = id
            return
        }
        
        editModel.lastClickAnnotationId = nil
        editModel.selectedAnnotationId = nil
        
        commitAllEdits()
        
        if editModel.selectedTool == .text || editModel.selectedTool == .numberedText {
            editModel.prepareForWrite()
            var cValue: Int? = nil
            if editModel.selectedTool == .numberedText {
                cValue = editModel.annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
            }
            let textItem = AnnotationItem(type: editModel.selectedTool, startPoint: point, endPoint: point, color: editModel.selectedColor, lineWidth: 2.0, text: "", fontStyle: editModel.selectedTextStyle, fontSize: editModel.selectedFontSize, counterValue: cValue)
            editModel.annotations.append(textItem)
            editModel.editingTextId = textItem.id
        } else {
            if editModel.currentAnnotation == nil {
                editModel.prepareForWrite()
                var cValue: Int? = nil
                if editModel.selectedTool == .aiMarker {
                    cValue = editModel.annotations.filter { $0.type == .aiMarker }.count + 1
                } else if editModel.selectedTool == .counter || editModel.selectedTool == .numberedText {
                    cValue = editModel.annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
                }
                
                let markerColor = editModel.selectedTool == .aiMarker ? TMDesign.Colors.purple.opacity(0.7) : editModel.selectedColor
                let isThickBrush = editModel.selectedTool == .highlighter || editModel.selectedTool == .blur || editModel.selectedTool == .mosaic
                let lw = isThickBrush ? editModel.selectedBrushSize : editModel.selectedLineWidth
                var newAnnotation = AnnotationItem(type: editModel.selectedTool, startPoint: point, endPoint: point, color: markerColor, lineWidth: lw, fontStyle: editModel.selectedTextStyle, fontSize: editModel.selectedFontSize, counterValue: cValue)
                if editModel.selectedTool == .rectText { newAnnotation.points = [point, point] }
                if newAnnotation.isFreehandTool { newAnnotation.points = [point] }
                editModel.currentAnnotation = newAnnotation
            }
            if editModel.currentAnnotation?.type == .rectText {
                editModel.currentAnnotation?.points?[1] = point
                editModel.currentAnnotation?.endPoint = point
            } else if editModel.currentAnnotation?.isFreehandTool == true {
                editModel.currentAnnotation?.points?.append(point)
                editModel.currentAnnotation?.endPoint = point
            } else {
                editModel.currentAnnotation?.endPoint = point
            }
        }
    }
    
    private func handleDragChange(_ point: CGPoint) {
        editModel.lastDragPoint = point
        let canvasBounds = CGRect(origin: .zero, size: originalSize)
        if let selectedId = editModel.selectedAnnotationId,
           let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }),
           let initialItem = editModel.annotationInitialItem,
           let start = editModel.annotationDragStartPoint {

            let dx = point.x - start.x
            let dy = point.y - start.y
            var updatedItem = initialItem

            if let handle = editModel.annotationActiveHandle {
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
            editModel.annotations[index] = AnnotationGeometry.clampedAnnotation(updatedItem, to: canvasBounds)
            return
        }

        if editModel.selectedTool != .text {
            if var current = editModel.currentAnnotation, current.isFreehandTool {
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
                editModel.currentAnnotation = current
            } else if editModel.currentAnnotation?.type == .rectText {
                editModel.currentAnnotation?.points?[1] = point
                editModel.currentAnnotation?.endPoint = point
            } else {
                editModel.currentAnnotation?.endPoint = point
            }
        }
    }
    
    private func handleDragEnd() {
        if let startPos = editModel.dragStartPos, let lastPos = editModel.lastDragPoint, let selectedId = editModel.selectedAnnotationId, let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }) {
            let dx = abs(lastPos.x - startPos.x)
            let dy = abs(lastPos.y - startPos.y)
            let isText = editModel.annotations[index].type == .text || editModel.annotations[index].type == .numberedText || editModel.annotations[index].type == .rectText
            let isCounter = editModel.annotations[index].type == .counter
            if isText && dx < 5 && dy < 5 && editModel.dragStartClickCount >= 2 {
                editModel.prepareForWrite()
                editModel.editingTextId = selectedId
            } else if isCounter && dx < 5 && dy < 5 && editModel.dragStartClickCount >= 2 {
                editModel.editingCounterId = selectedId
            }
        }
        editModel.dragStartPos = nil
        editModel.lastDragPoint = nil
        
        if editModel.annotationInitialItem != nil {
            let changed = (editModel.undoStack.last != editModel.annotations)
            editModel.annotationInitialItem = nil
            editModel.annotationDragStartPoint = nil
            editModel.annotationActiveHandle = nil
            if !changed { if !editModel.undoStack.isEmpty { _ = editModel.undoStack.removeLast() } }
            return
        }
        
        if editModel.selectedTool != .text {
            if let final = editModel.currentAnnotation {
                var shouldSave = false
                if final.isFreehandTool {
                    if let points = final.points, points.count > 3 { editModel.annotations.append(final); shouldSave = true }
                } else {
                    let dx = abs(final.startPoint.x - final.endPoint.x)
                    let dy = abs(final.startPoint.y - final.endPoint.y)
                    if final.type == .counter || final.type == .aiMarker || dx > 5 || dy > 5 { editModel.annotations.append(final); shouldSave = true }
                }
                if shouldSave, final.type == .rectText, let idx = editModel.annotations.indices.last {
                    let p0 = editModel.annotations[idx].points?[0] ?? editModel.annotations[idx].startPoint
                    let p1 = editModel.annotations[idx].points?[1] ?? editModel.annotations[idx].endPoint
                    let minX = min(p0.x, p1.x)
                    let maxX = max(p0.x, p1.x)
                    let minY = min(p0.y, p1.y)
                    let maxY = max(p0.y, p1.y)
                    let rectWidth = maxX - minX
                    editModel.annotations[idx].points = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)]
                    editModel.annotations[idx].startPoint = CGPoint(x: minX, y: minY)
                    let offset = CGSize(width: rectWidth + 16, height: 0)
                    editModel.annotations[idx].calloutOffset = offset
                    editModel.annotations[idx].endPoint = CGPoint(x: minX + offset.width + 120, y: minY + offset.height + 30)
                    editModel.annotations[idx].customWidth = 120
                    editModel.selectedAnnotationId = editModel.annotations[idx].id
                    editModel.editingTextId = editModel.annotations[idx].id
                }
                if !shouldSave { if !editModel.undoStack.isEmpty { _ = editModel.undoStack.removeLast() } }
            }
            editModel.currentAnnotation = nil
        }
    }

    private func updateSelectedAnnotation(color: Color? = nil, fontSize: CGFloat? = nil, lineWidth: CGFloat? = nil, style: TextStyle? = nil) {
        guard let selectedId = editModel.selectedAnnotationId,
              let index = editModel.annotations.firstIndex(where: { $0.id == selectedId }) else { return }
        
        var item = editModel.annotations[index]
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
            editModel.prepareForWrite()
            editModel.annotations[index] = item
        }
    }
    
    private func handleSelectionChange(to newId: UUID?) {
        guard let id = newId, let item = editModel.annotations.firstIndex(where: { $0.id == id }).map({ editModel.annotations[$0] }) else { return }
        
        editModel.selectedColor = item.color
        if item.type == .text || item.type == .numberedText || item.type == .rectText || item.type == .counter || item.type == .aiMarker {
            editModel.selectedFontSize = item.fontSize ?? 16.0
        } else {
            editModel.selectedLineWidth = item.lineWidth
        }
        if let style = item.fontStyle {
            editModel.selectedTextStyle = style
        }
    }
    
    @MainActor
    private func pinScreenshot() {
        let exportView = AnnotationCanvasLayer(
            image: image,
            displaySize: originalSize,
            annotations: editModel.annotations,
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
                HistoryManager.shared.updateRecord(id: rId, annotations: editModel.annotations, finalImage: cgImage)
            } else {
                CaptureEngine.shared.saveToDisk(image: cgImage, originalImage: image, fileName: "Screenshot_Annotated", annotations: editModel.annotations)
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
            let aiMarkers = editModel.annotations.filter { $0.type == .aiMarker }
            
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
            AppLogger.ui.debug("📋 [Annotation] AI \(copyCoords ? "坐标" : "原图")已复制")
            
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: editModel.annotations, finalImage: fullImageForHistory)
            } else {
                CaptureEngine.shared.saveToDisk(image: fullImageForHistory, originalImage: image, fileName: "Screenshot_Annotated", annotations: editModel.annotations)
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

            AppLogger.ui.debug("📋 [Annotation] 普通标注图已复制")
            
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
        if editModel.annotations.isEmpty && editModel.currentAnnotation == nil {
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: [], finalImage: image)
            } else {
                CaptureEngine.shared.saveToDisk(image: image, fileName: "Screenshot_Annotated")
            }
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])

            AppLogger.ui.info("✅ [Annotation] 标注成功导出并保存！")

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
                HistoryManager.shared.updateRecord(id: rId, annotations: editModel.annotations, finalImage: cgImage)
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

            AppLogger.ui.info("✅ [Annotation] 标注成功导出并保存！")

            withAnimation(.spring()) {
                toastMessage = LanguageManager.shared.localizedString(forKey: "Saved_And_Copied")
                showToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onClose()
            }
        } else {
            AppLogger.ui.error("❌ [Annotation] ImageRenderer 渲染失败")
            onClose()
        }
    }
    
    @MainActor
    private func generateImageForExport(excludeAIMarkers: Bool = true) -> CGImage? {
        let exportAnnotations = excludeAIMarkers ? editModel.annotations.filter { $0.type != .aiMarker } : editModel.annotations
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
        if editModel.annotations.isEmpty {
            targetImage = image
        } else {
            let exportView = AnnotationCanvasLayer(
                image: image,
                displaySize: originalSize,
                annotations: editModel.annotations,
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
                AppLogger.ui.error("⚠️ [OCR] 未识别到文字或发生错误: \(String(describing: error))")
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
            AppLogger.ui.warning("⚠️ [Translation] 没有可翻译的文本")
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
            onDelete: deleteSelectedAnnotation,
            onPin: pinScreenshot,
            onOCR: { performOCR(isForTranslation: false) },
            onTranslate: { performOCR(isForTranslation: true) },
            onCancel: onClose,
            onConfirm: exportAndClose,
            onGenerateDragURL: { return generateDragURL() },
            isEditingText: editModel.editingTextId != nil || editModel.editingCounterId != nil,
            aiMarkerCount: editModel.annotations.filter({ $0.type == .aiMarker }).count,
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

    static let ciContext = CIContext()
    /// 缓存：key = "width x height - effectType"，value = 预计算效果图
    /// 同一张截图的 blur/mosaic 效果相同，所有实例共享缓存
    private static var effectCache: [String: NSImage] = [:]
    private static let effectCacheLock = NSLock()

    /// 清除缓存（新截图会话开始时调用）
    static func clearEffectCache() {
        effectCacheLock.lock()
        defer { effectCacheLock.unlock() }
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
        Self.effectCacheLock.lock()
        let cached = Self.effectCache[key]
        Self.effectCacheLock.unlock()
        if let cached = cached {
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
                filter.radius = Float(EffectConfig.blurRadius)
                resultCGImage = filter.outputImage.flatMap { out in
                    Self.ciContext.createCGImage(out, from: ciImage.extent)
                }
            } else if effectType == .mosaic {
                // CoreGraphics 双向采样，产生均匀方块
                resultCGImage = createMosaicCGImage(cgImage, blockSize: EffectConfig.mosaicBlockSize)
            }

            if let result = resultCGImage {
                let nsImage = NSImage(cgImage: result, size: size)
                DispatchQueue.main.async {
                    // 存入缓存供其他实例使用
                    Self.effectCacheLock.lock()
                    Self.effectCache[key] = nsImage
                    Self.effectCacheLock.unlock()
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
                let numberOffset = (item.type == .numberedText) ? (fontSize * NumberedCircleConfig.renderSizeMultiplier + 8) : 0
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
                            Circle().fill(item.color).frame(width: fontSize * NumberedCircleConfig.renderSizeMultiplier, height: fontSize * NumberedCircleConfig.renderSizeMultiplier)
                            if isEditingCounterState {
                                AnyView(AutoSizingTextView(
                                text: Binding(
                                    get: { item.customCounterString ?? (item.counterValue != nil ? String(item.counterValue!) : "1") },
                                    set: { onCounterChanged?(item.id, $0) }
                                ),
                                fontSize: fontSize * 0.8,
                                textColor: item.color == .white ? .black : .white,
                                customWidth: fontSize * NumberedCircleConfig.renderSizeMultiplier,
                                maxWidth: fontSize * 2.0,
                                isEditable: true,
                                placeholder: nil,
                                commitOnReturn: true,
                                onCommit: { onTextCommit?() }
                            )
                            .frame(width: fontSize * NumberedCircleConfig.renderSizeMultiplier, height: fontSize * NumberedCircleConfig.renderSizeMultiplier))
                            } else {
                                AnyView(Text(countStr)
                                    .font(.system(size: fontSize * 0.8, weight: .bold))
                                    .foregroundColor(item.color == .white ? .black : .white))
                            }
                        }
                        .frame(width: fontSize * NumberedCircleConfig.renderSizeMultiplier, height: fontSize * NumberedCircleConfig.renderSizeMultiplier)
                        .position(x: item.startPoint.x, y: item.startPoint.y)
                        .contentShape(Circle())
                        .onTapGesture(count: 2) {
                            NotificationCenter.default.post(name: .counterDoubleTapped, object: item.id)
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
                            NotificationCenter.default.post(name: .annotationDoubleTapped, object: item.id)
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
                    .frame(width: size * NumberedCircleConfig.renderSizeMultiplier, height: size * NumberedCircleConfig.renderSizeMultiplier)
                    
                    if isEditingCounterState {
                        AnyView(AutoSizingTextView(
                            text: Binding(
                                get: { item.customCounterString ?? (item.counterValue != nil ? String(item.counterValue!) : "1") },
                                set: { onCounterChanged?(item.id, $0) }
                            ),
                            fontSize: size * 0.8,
                            textColor: item.color == .white ? .black : .white,
                            customWidth: size * NumberedCircleConfig.renderSizeMultiplier,
                            maxWidth: size * 2.0,
                            isEditable: true,
                            placeholder: nil,
                            commitOnReturn: true,
                            onCommit: { onTextCommit?() }
                        )
                        .frame(width: size * NumberedCircleConfig.renderSizeMultiplier, height: size * NumberedCircleConfig.renderSizeMultiplier))
                    } else {
                        AnyView(Text(item.displayCounterString)
                            .font(.system(size: size * 0.8, weight: .bold))
                            .foregroundColor(item.color == .white ? .black : .white))
                    }
                }
                .frame(width: size * NumberedCircleConfig.renderSizeMultiplier, height: size * NumberedCircleConfig.renderSizeMultiplier)
                .position(x: item.endPoint.x, y: item.endPoint.y)
                .contentShape(Circle())
                .onTapGesture(count: 2) {
                    NotificationCenter.default.post(name: .counterDoubleTapped, object: item.id)
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
                        NotificationCenter.default.post(name: .commitTextEdit, object: nil)
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
                    NotificationCenter.default.post(name: .commitTextEdit, object: nil)
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
                    NotificationCenter.default.post(name: .commitTextEdit, object: nil)
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
