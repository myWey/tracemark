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
    let recordId: UUID?
    let onClose: () -> Void
    
    @State private var annotations: [AnnotationItem] = []
    @State private var currentAnnotation: AnnotationItem? = nil
    @State private var editingTextId: UUID? = nil
    @State private var showToast: Bool = false
    
    @State private var selectedTool: AnnotationToolType = .rectangle
    @State private var selectedColor: Color = .red
    
    @State private var selectedFontSize: CGFloat = 16.0
    @State private var selectedLineWidth: CGFloat = 4.0
    @State private var selectedBrushSize: CGFloat = 24.0
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
    
    // 双击检测状态
    @State private var lastClickTime: Double = 0
    @State private var lastClickAnnotationId: UUID? = nil
    
    @State private var dragStartPos: CGPoint? = nil
    @State private var dragStartClickCount: Int = 1
    @State private var lastDragPoint: CGPoint? = nil
    
    // OCR & Translation 状态
    @State private var ocrResultText: String = ""
    @State private var showOCRPanel: Bool = false
    @State private var showTranslation: Bool = false
    @State private var isOCRLoading: Bool = false

    public init(
        image: CGImage,
        displaySize: CGSize,
        initialAnnotations: [AnnotationItem] = [],
        recordId: UUID? = nil,
        onClose: @escaping () -> Void
    ) {
        self.image = image
        self.originalSize = displaySize
        self.recordId = recordId
        self.onClose = onClose
        self._annotations = State(initialValue: initialAnnotations)
        self._undoStack = State(initialValue: [])
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
    
    public var body: some View {
        HStack(spacing: 0) {
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
                        // Canvas is exactly the visual size, placed at offset
                        AnnotationCanvasLayer(
                            image: image,
                            displaySize: originalSize,
                            annotations: annotations,
                            currentAnnotation: currentAnnotation,
                            selectedAnnotationId: selectedAnnotationId,
                            editingTextId: editingTextId,
                            onTextChanged: { id, newText in
                                if let index = annotations.firstIndex(where: { $0.id == id }) {
                                    annotations[index].text = newText
                                }
                            },
                            onTextCommit: {
                                if let index = annotations.firstIndex(where: { $0.id == editingTextId }) {
                                    let text = annotations[index].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    if text.isEmpty {
                                        prepareForWrite()
                                        annotations.remove(at: index)
                                    }
                                }
                                editingTextId = nil
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
                                    if selectedTool == .pencil || selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic {
                                        NSCursor.transparent.set()
                                    } else {
                                        NSCursor.crosshair.set()
                                    }
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
                            onDelete: deleteSelectedAnnotation
                        )
                        .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                        .allowsHitTesting(editingTextId == nil)
                        
                        // 7. PSD-style 圆形画笔光标
                        if isHoveringCanvas && (selectedTool == .pencil || selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic) {
                            let brushSize: CGFloat = {
                                let lw = max(1.0, selectedLineWidth / 4.0)
                                let baseSize: CGFloat
                                if selectedTool == .pencil {
                                    baseSize = lw
                                } else {
                                    baseSize = max(20.0, lw * 2.0)
                                }
                                return baseSize * scale
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
                    .frame(width: containerGeo.size.width, height: containerGeo.size.height)
                }
                .clipped()
                
                // 双层工具栏
                UnifiedToolbarView(
                    selectedTool: $selectedTool,
                    selectedColor: $selectedColor,
                    selectedFontSize: $selectedFontSize,
                    selectedLineWidth: $selectedLineWidth,
                    selectedBrushSize: $selectedBrushSize,
                    selectedTextStyle: $selectedTextStyle,
                    hasUndo: !undoStack.isEmpty,
                    hasRedo: !redoStack.isEmpty,
                    hasSelection: selectedAnnotationId != nil,
                    onUndo: undo,
                    onRedo: redo,
                    onDelete: deleteSelectedAnnotation,
                    onPin: pinScreenshot,
                    onOCR: { performOCR(isForTranslation: false) },
                    onTranslate: { performOCR(isForTranslation: true) },
                    onCancel: onClose,
                    onConfirm: exportAndClose,
                    onGenerateDragURL: { return generateDragURL() }
                )
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
            
            // 成功提示 Toast
            if showToast {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                    Text("已复制到剪贴板")
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
                OCRResultPanel(text: $ocrResultText, onClose: {
                    withAnimation { showOCRPanel = false }
                }, onTranslate: {
                    showTranslation = true
                })
                .transition(.move(edge: .trailing))
                .zIndex(101)
            }
        }
        .applyTranslationPresentation(isPresented: $showTranslation, text: ocrResultText)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: selectedTool) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerPostCaptureAction"))) { notification in
            if let action = notification.object as? PostCaptureAction {
                if action == .ocr {
                    performOCR(isForTranslation: false)
                } else if action == .translate {
                    performOCR(isForTranslation: true)
                }
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
        
        // 先检查是否点中了某个控制柄
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let itemRect = annotations[index].rect
            if let handle = hitTestHandle(point: point, rect: itemRect) {
                return (selectedId, handle)
            }
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
        
        // 再检查是否点中了某个标注的包围盒
        for item in annotations.reversed() {
            if item.rect.contains(point) {
                return (item.id, nil)
            }
        }
        
        return nil
    }
    
    private func handleHover(_ point: CGPoint) {
        if let (_, handle) = hitTestAnnotation(point: point) {
            if handle == .calloutOrigin {
                NSCursor.pointingHand.set()
            } else if handle != nil {
                NSCursor.crosshair.set()
            } else {
                NSCursor.openHand.set()
            }
            return
        }
        
        let isBrush = selectedTool == .pencil || selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic
        if isBrush {
            NSCursor.transparent.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
    
    private func handleDragStart(_ point: CGPoint, clickCount: Int) {
        dragStartClickCount = clickCount
        dragStartPos = point
        lastDragPoint = point
        let now = ProcessInfo.processInfo.systemUptime
        let clickInterval = now - lastClickTime
        lastClickTime = now
        
        if let (id, handle) = hitTestAnnotation(point: point) {
            prepareForWrite()
            selectedAnnotationId = id
            annotationActiveHandle = handle
            annotationInitialItem = annotations.first(where: { $0.id == id })
            annotationDragStartPoint = point
            
            if handle == nil && lastClickAnnotationId == id && clickInterval < 0.3 {
                let type = annotations.first(where: { $0.id == id })?.type
                if type == .text || type == .numberedText {
                    editingTextId = id
                }
            }
            lastClickAnnotationId = id
            return
        }
        
        lastClickAnnotationId = nil
        selectedAnnotationId = nil
        
        if editingTextId != nil { editingTextId = nil }
        
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
                if selectedTool == .counter || selectedTool == .numberedText {
                    cValue = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
                }
                let isThickBrush = selectedTool == .highlighter || selectedTool == .blur || selectedTool == .mosaic
                let lw = isThickBrush ? selectedBrushSize : selectedLineWidth
                var newAnnotation = AnnotationItem(type: selectedTool, startPoint: point, endPoint: point, color: selectedColor, lineWidth: lw, fontStyle: selectedTextStyle, fontSize: selectedFontSize, counterValue: cValue)
                if newAnnotation.isFreehandTool { newAnnotation.points = [point] }
                currentAnnotation = newAnnotation
            }
            if currentAnnotation?.isFreehandTool == true { currentAnnotation?.points?.append(point) }
            currentAnnotation?.endPoint = point
        }
    }
    
    private func handleDragChange(_ point: CGPoint) {
        lastDragPoint = point
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
                    case .bottomRight: newRect.size.width = max(5, initRect.size.width + dx); newRect.size.height = max(5, initRect.size.height + dy)
                    case .calloutOrigin: break
                    }
                    updatedItem.resize(to: newRect, from: initRect)
                }
            } else {
                if updatedItem.type == .numberedText {
                    let oldOffset = updatedItem.calloutOffset ?? CGSize(width: 16.0, height: -45.0)
                    updatedItem.calloutOffset = CGSize(width: oldOffset.width + dx, height: oldOffset.height + dy)
                    updatedItem.endPoint = CGPoint(x: updatedItem.endPoint.x + dx, y: updatedItem.endPoint.y + dy)
                } else {
                    updatedItem.move(by: CGSize(width: dx, height: dy))
                }
            }
            annotations[index] = updatedItem
            return
        }
        
        if selectedTool != .text {
            if currentAnnotation?.isFreehandTool == true {
                currentAnnotation?.points?.append(point)
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
            let isText = annotations[index].type == .text || annotations[index].type == .numberedText
            if isText && dx < 5 && dy < 5 && dragStartClickCount >= 2 {
                prepareForWrite()
                editingTextId = selectedId
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
                    if final.type == .counter || dx > 5 || dy > 5 { annotations.append(final); shouldSave = true }
                }
                if !shouldSave { if !undoStack.isEmpty { _ = undoStack.removeLast() } }
            }
            currentAnnotation = nil
        }
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
        
        if let cgImage = renderer.cgImage {
            PinManager.shared.pin(image: cgImage)
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: annotations, finalImage: cgImage)
            } else {
                CaptureEngine.shared.saveToDisk(image: cgImage, fileName: "Screenshot_Annotated")
            }
            
            onClose()
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
                showToast = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onClose()
            }
            return
        }
        
        if let cgImage = generateImageForExport() {
            if let rId = recordId {
                HistoryManager.shared.updateRecord(id: rId, annotations: annotations, finalImage: cgImage)
            } else {
                CaptureEngine.shared.saveToDisk(image: cgImage, fileName: "Screenshot_Annotated")
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])
            
            print("✅ [Annotation] 标注成功导出并保存！")
            
            withAnimation(.spring()) {
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
    private func generateImageForExport() -> CGImage? {
        let exportView = AnnotationCanvasLayer(
            image: image,
            displaySize: originalSize,
            annotations: annotations,
            currentAnnotation: nil,
            selectedAnnotationId: nil,
            editingTextId: nil,
            onTextChanged: { _, _ in },
            onTextCommit: {},
            onSizeChanged: { _, _ in }
        )
        
        let renderer = ImageRenderer(content: exportView)
        let scaleFactor = CGFloat(image.width) / originalSize.width
        renderer.scale = scaleFactor
        
        return renderer.cgImage
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
        
        TextRecognitionService.shared.recognizeText(from: finalImage) { text, error in
            isOCRLoading = false
            let result = text ?? ""
            
            if result.isEmpty {
                print("⚠️ [OCR] 未识别到文字或发生错误: \(String(describing: error))")
                self.ocrResultText = "未识别到文字"
            } else {
                self.ocrResultText = result
            }
            
            if isForTranslation {
                self.showTranslation = true
            } else {
                self.showOCRPanel = true
            }
        }
    }
}

/// 将需要渲染的层单独抽离出来
struct AnnotationCanvasLayer: View {
    let image: CGImage
    let displaySize: CGSize
    let annotations: [AnnotationItem]
    let currentAnnotation: AnnotationItem?
    
    // 编辑状态相关
    var selectedAnnotationId: UUID? = nil
    var editingTextId: UUID? = nil
    var onTextChanged: ((UUID, String) -> Void)? = nil
    var onTextCommit: (() -> Void)? = nil
    var onSizeChanged: ((UUID, CGSize) -> Void)? = nil
    var clipRect: CGRect? = nil
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 底图
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)
                .onTapGesture {
                    if editingTextId != nil {
                        onTextCommit?()
                    }
                }
            
            // 将所有标注放在一个容器中以便统一裁切
            ZStack(alignment: .topLeading) {
                // 占位全屏，必须有一点不透明度，否则会被 SwiftUI 的 mask 视觉边界计算优化掉
                Color.white.opacity(0.001)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .allowsHitTesting(false)
                
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
                
                // 已有的标注图层
                ForEach(annotations) { item in
                    AnnotationShapeView(
                        item: item,
                        isEditing: item.id == editingTextId,
                        onTextChanged: onTextChanged,
                        onTextCommit: onTextCommit,
                        onSizeChanged: onSizeChanged,
                        baseImage: image,
                        displaySize: displaySize,
                        clipRect: clipRect // 传入
                    )
                    
                    if item.id == selectedAnnotationId {
                        // 绘制选中态包围盒
                        Rectangle()
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: item.rect.width, height: item.rect.height)
                            .position(x: item.rect.midX, y: item.rect.midY)
                            .allowsHitTesting(false)
                        
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
                
                // 当前正在绘制的标注图层
                if let current = currentAnnotation {
                    AnnotationShapeView(
                        item: current,
                        isEditing: false,
                        onTextChanged: nil,
                        onTextCommit: nil,
                        baseImage: image,
                        displaySize: displaySize,
                        clipRect: clipRect // 传入
                    )
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            // 如果提供了 clipRect，则严格裁切，否则不裁切
            .clipShape(Path(clipRect ?? CGRect(origin: .zero, size: displaySize)))
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .background(Color.clear)
    }
}

/// 单个标注形状渲染
struct AnnotationShapeView: View {
    let item: AnnotationItem
    let isEditing: Bool
    let onTextChanged: ((UUID, String) -> Void)?
    let onTextCommit: (() -> Void)?
    var onSizeChanged: ((UUID, CGSize) -> Void)? = nil
    
    var baseImage: CGImage? = nil
    var displaySize: CGSize? = nil
    var clipRect: CGRect? = nil // 新增
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Group {
            switch item.type {
            case .rectangle:
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: item.lineWidth / 2, dy: item.lineWidth / 2)
                    context.stroke(Path(rect), with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth))
                }
                .frame(width: item.rect.width, height: item.rect.height)
                .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .filledRectangle:
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(item.color))
                }
                .frame(width: item.rect.width, height: item.rect.height)
                .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .ellipse:
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: item.lineWidth / 2, dy: item.lineWidth / 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth))
                }
                .frame(width: item.rect.width, height: item.rect.height)
                    .position(x: item.rect.midX, y: item.rect.midY)
                    
            case .line:
                Canvas { context, size in
                    var path = Path()
                    path.move(to: item.startPoint)
                    path.addLine(to: item.endPoint)
                    context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth))
                }
                
            case .arrow:
                ArrowView(start: item.startPoint, end: item.endPoint, color: item.color, lineWidth: item.lineWidth)
                    
            case .pencil:
                if let points = item.points, points.count > 1 {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: points.first!)
                        path.addLines(points)
                        context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
                
            case .highlighter:
                if let points = item.points, points.count > 1 {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: points.first!)
                        path.addLines(points)
                        context.stroke(path, with: .color(item.color.opacity(0.5)), style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
                    
            case .text, .numberedText:
                let fontSize = item.fontSize ?? 24.0
                let fontStyle = item.fontStyle ?? .standard
                
                let rightEdge = clipRect?.maxX ?? displaySize?.width ?? 800
                let numberOffset = (item.type == .numberedText) ? (fontSize * 1.5 + 8) : 0
                let limitWidth = rightEdge - item.startPoint.x - numberOffset - 20
                let finalMaxWidth = max(50, limitWidth)
                
                // Helper function to apply text style
                let styledText: (String) -> AnyView = { text in
                    let getContrastColor: (Color) -> Color = { bg in
                        let nsColor = NSColor(bg).usingColorSpace(.sRGB) ?? NSColor(bg)
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                        nsColor.getRed(&r, green: &g, blue: &b, alpha: nil)
                        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                        return luminance > 0.6 ? .black : .white
                    }
                    
                    let t = Text(text)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(fontStyle == .outlined ? .clear : (fontStyle == .standard ? item.color : getContrastColor(item.color)))
                    
                    var view: AnyView
                    if fontStyle == .outlined {
                        // Outline simulation with shadow
                        view = AnyView(Text(text)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: item.color, radius: 1, x: 1, y: 1)
                            .shadow(color: item.color, radius: 1, x: -1, y: -1))
                    } else if fontStyle == .boxed || fontStyle == .roundedBoxed {
                        view = AnyView(t.padding(8).background(item.color.opacity(0.85)).cornerRadius(fontStyle == .roundedBoxed ? 12 : 4))
                    } else {
                        view = AnyView(t)
                    }
                    return view
                }
                
                ZStack(alignment: .topLeading) {
                    if item.type == .numberedText, let count = item.counterValue {
                        let offset = item.calloutOffset ?? CGSize(width: 16.0, height: -45.0)
                        
                        // 连接线 (从 startPoint 到 text box)
                        Canvas { context, size in
                            var path = Path()
                            path.move(to: item.startPoint)
                            
                            // textOrigin is the TOP-LEFT corner of the text box
                            let textOrigin = CGPoint(x: item.startPoint.x + offset.width, y: item.startPoint.y + offset.height)
                            let textWidth = item.rect.width
                            let textHeight = item.rect.height
                            let textCenterY = textOrigin.y + textHeight / 2
                            
                            // line connects to left or right edge depending on relative position
                            let isLeft = offset.width < 0
                            let textAnchorX = isLeft ? textOrigin.x + textWidth : textOrigin.x
                            
                            path.addLine(to: CGPoint(x: textAnchorX, y: textCenterY))
                            context.stroke(path, with: .color(item.color), style: StrokeStyle(lineWidth: max(2, fontSize * 0.15)))
                        }
                        
                        // 序号点 (使用 Canvas 绘制圆形背景以修复 Intel 渲染 BUG)
                        ZStack {
                            Canvas { context, size in
                                context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(item.color))
                            }
                            .frame(width: fontSize * 1.5, height: fontSize * 1.5)
                            
                            Text("\(count)")
                                .font(.system(size: fontSize * 0.8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .position(x: item.startPoint.x, y: item.startPoint.y)
                        
                        // 独立文本区 (Offset by calloutOffset)
                        Group {
                            if isEditing {
                                TextField("输入文本...", text: Binding(
                                    get: { item.text ?? "" },
                                    set: { onTextChanged?(item.id, $0) }
                                ), axis: .vertical)
                                .onSubmit {
                                    onTextCommit?()
                                }
                                .focused($isFocused)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: fontSize, weight: .bold))
                                .foregroundColor(fontStyle == .standard ? item.color : .white)
                                // 设置最大最小宽度
                                .frame(minWidth: 100, maxWidth: finalMaxWidth, alignment: .leading)
                                .padding(8)
                                .background(fontStyle == .standard ? Color.black.opacity(0.85) : Color.black.opacity(0.3))
                                .cornerRadius(8)
                                .fixedSize(horizontal: false, vertical: true)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isFocused = true
                                    }
                                }
                            } else {
                                styledText(item.text?.isEmpty == false ? item.text! : " ")
                            }
                        }
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
                        .offset(x: item.startPoint.x + offset.width,
                                y: item.startPoint.y + offset.height)
                        
                    } else {
                        // 常规文本
                        HStack(alignment: .top, spacing: 0) {
                            if isEditing {
                                TextField("输入文本...", text: Binding(
                                    get: { item.text ?? "" },
                                    set: { onTextChanged?(item.id, $0) }
                                ), axis: .vertical)
                                .onSubmit {
                                    onTextCommit?()
                                }
                                .focused($isFocused)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: fontSize, weight: .bold))
                                .foregroundColor(fontStyle == .standard ? item.color : .white)
                                // 设置最大最小宽度
                                .frame(minWidth: 100, maxWidth: finalMaxWidth, alignment: .leading)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                                .fixedSize(horizontal: false, vertical: true)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isFocused = true
                                    }
                                }
                            } else {
                                styledText(item.text?.isEmpty == false ? item.text! : " ")
                                    .frame(maxWidth: finalMaxWidth, alignment: .leading)
                            }
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.size) { newSize in
                                        onSizeChanged?(item.id, newSize)
                                    }
                            }
                        )
                        .offset(x: item.startPoint.x, y: item.startPoint.y)
                    }
                }
                    
            case .blur, .mosaic:
                if let points = item.points, points.count > 1 {
                    ImageEffectView(
                        type: item.type,
                        rect: item.rect,
                        baseImage: baseImage,
                        displaySize: displaySize
                    )
                    .mask(
                        Canvas { context, size in
                            var path = Path()
                            path.move(to: points.first!)
                            path.addLines(points)
                            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    )
                } else {
                    ImageEffectView(
                        type: item.type,
                        rect: item.rect,
                        baseImage: baseImage,
                        displaySize: displaySize
                    )
                }
            
            case .spotlight:
                Color.clear
                    .frame(width: item.rect.width, height: item.rect.height)
                    
            case .counter:
                let size = item.fontSize ?? 24.0
                ZStack {
                    Canvas { context, sz in
                        context.fill(Path(ellipseIn: CGRect(origin: .zero, size: sz)), with: .color(item.color))
                    }
                    .frame(width: size * 1.5, height: size * 1.5)
                    
                    Text("\(item.counterValue ?? 1)")
                        .font(.system(size: size * 0.8, weight: .bold))
                        .foregroundColor(.white)
                }
                .position(x: item.endPoint.x, y: item.endPoint.y)
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
        case .counter: return "1.circle"
        case .pencil: return "paintbrush.pointed"
        case .highlighter: return "marker.fill"
        case .blur: return "drop"
        case .mosaic: return "square.grid.3x3.topleft.filled"
        case .spotlight: return "theatermasks"
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

extension View {
    @ViewBuilder
    func applyTranslationPresentation(isPresented: Binding<Bool>, text: String) -> some View {
        if #available(macOS 14.4, *) {
            self.translationPresentation(isPresented: isPresented, text: text)
        } else {
            self
        }
    }
}
