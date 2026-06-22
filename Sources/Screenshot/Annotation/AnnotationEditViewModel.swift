import SwiftUI
import CoreGraphics

/// 标注编辑共享 ViewModel
/// 持有两个 RootView（AnnotationRootView + OverlayRootView）的共享标注编辑状态与方法，
/// 消除重复代码。行为差异通过 Behavior 配置参数化。
@MainActor
final class AnnotationEditViewModel: ObservableObject {

    // MARK: - 性能配置

    /// 笔触点采样最小距离阈值：小于此距离的点被丢弃，降低 SwiftUI 重绘频率
    /// Intel 核显用更大阈值（5.0）减少重绘压力；Apple Silicon 用 3.0 保持笔触精度
    #if arch(x86_64)
    static let brushDistanceThreshold: CGFloat = 5.0
    #else
    static let brushDistanceThreshold: CGFloat = 3.0
    #endif

    // MARK: - 行为配置

    /// 两个视图的行为差异配置
    struct Behavior {
        /// aiMarker 点击即保存（AnnotationRootView=true, OverlayWindow=false）
        var aiMarkerSaveOnClick: Bool
        /// 双击检测最大间隔（秒）
        var doubleClickInterval: TimeInterval
        /// 是否信任系统 clickCount（AnnotationRootView=true, OverlayWindow=false）
        var trustClickCount: Bool
        /// 是否为 aiMarker 同步 fontSize（AnnotationRootView=true, OverlayWindow=false）
        var syncFontSizeForAiMarker: Bool
        /// 是否为 brush 类工具（highlighter/blur/mosaic）同步 brushSize（AnnotationRootView=false, OverlayWindow=true）
        var syncBrushSizeForBrushTools: Bool
        /// 删空文本时是否入 undo 栈（AnnotationRootView=false, OverlayWindow=true）
        var includeEmptyTextInUndo: Bool
        /// hitTestHandle 角落命中区最小值（AnnotationRootView=10, OverlayWindow=5）
        var cornerMinHitZone: CGFloat
        /// hitTestHandle 边缘命中区（nil=不区分角落和边缘，AnnotationRootView=nil, OverlayWindow=20）
        var edgeHitZone: CGFloat?
        /// aiMarker 是否使用紫色半透明（AnnotationRootView=true, OverlayWindow=false）
        var usePurpleForAiMarker: Bool

        /// AnnotationRootView 行为配置
        static let annotationConfig = Behavior(
            aiMarkerSaveOnClick: true,
            doubleClickInterval: 0.5,
            trustClickCount: true,
            syncFontSizeForAiMarker: true,
            syncBrushSizeForBrushTools: false,
            includeEmptyTextInUndo: false,
            cornerMinHitZone: 10,
            edgeHitZone: nil,
            usePurpleForAiMarker: true
        )

        /// OverlayRootView 行为配置
        static let overlayConfig = Behavior(
            aiMarkerSaveOnClick: false,
            doubleClickInterval: 0.3,
            trustClickCount: false,
            syncFontSizeForAiMarker: false,
            syncBrushSizeForBrushTools: true,
            includeEmptyTextInUndo: true,
            cornerMinHitZone: 5,
            edgeHitZone: 20,
            usePurpleForAiMarker: false
        )
    }

    let behavior: Behavior

    // MARK: - 共享标注状态

    @Published var annotations: [AnnotationItem]
    @Published var currentAnnotation: AnnotationItem? = nil
    @Published var editingTextId: UUID? = nil
    @Published var editingCounterId: UUID? = nil

    // MARK: - 工具状态

    @Published var selectedTool: AnnotationToolType
    @Published var selectedColor: Color = TMDesign.Colors.red
    @Published var selectedFontSize: CGFloat = 16.0
    @Published var selectedLineWidth: CGFloat = 4.0
    @Published var selectedBrushSize: CGFloat = 24.0
    @Published var selectedTextStyle: TextStyle = .standard

    // MARK: - 标注选中与调整状态

    @Published var selectedAnnotationId: UUID? = nil
    @Published var annotationActiveHandle: DragHandle? = nil
    @Published var annotationInitialItem: AnnotationItem? = nil
    @Published var annotationDragStartPoint: CGPoint? = nil

    // MARK: - 撤销/重做栈

    @Published var undoStack: [[AnnotationItem]] = []
    @Published var redoStack: [[AnnotationItem]] = []

    // MARK: - hover 状态

    @Published var hoverPoint: CGPoint
    @Published var isHoveringCanvas: Bool = false

    // MARK: - 双击检测状态

    @Published var lastClickTime: Double = 0
    @Published var lastClickAnnotationId: UUID? = nil

    // MARK: - 拖拽状态

    @Published var dragStartPos: CGPoint? = nil
    @Published var dragStartClickCount: Int = 1
    @Published var lastDragPoint: CGPoint? = nil

    // MARK: - Init

    init(
        annotations: [AnnotationItem] = [],
        behavior: Behavior,
        selectedTool: AnnotationToolType,
        hoverPoint: CGPoint = .zero
    ) {
        self.annotations = annotations
        self.behavior = behavior
        self.selectedTool = selectedTool
        self.hoverPoint = hoverPoint
    }

    // MARK: - 撤销/重做方法

    func prepareForWrite() {
        if undoStack.isEmpty || undoStack.last != annotations {
            undoStack.append(annotations)
            redoStack.removeAll()
        }
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
    }

    // MARK: - 序号重排

    func reorderCounters(after id: UUID, newString: String) {
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

    // MARK: - hitTest

    func hitTestAnnotation(point: CGPoint, rectTextBounds: (AnnotationItem) -> CGRect?) -> (UUID, DragHandle?)? {
        // 检查是否点中了 NumberedText 的起始点圆圈
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let item = annotations[index]
            if item.type == .numberedText {
                let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.renderSizeMultiplier
                let circleRect = CGRect(x: item.startPoint.x - size/2, y: item.startPoint.y - size/2, width: size, height: size)
                if circleRect.contains(point) {
                    return (selectedId, .calloutOrigin)
                }
            }
        }

        // 先检查是否点中了某个控制柄（文本框控制柄）
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            let item = annotations[index]
            let itemRect = item.rect
            let isText = item.type == .text || item.type == .numberedText || item.type == .rectText

            if let handle = AnnotationGeometry.hitTestHandle(point: point, in: itemRect, cornerMinHitZone: behavior.cornerMinHitZone, edgeHitZone: behavior.edgeHitZone) {
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
                let size = (item.fontSize ?? 16.0) * NumberedCircleConfig.renderSizeMultiplier
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

    // MARK: - 选中标注更新

    func updateSelectedAnnotation(color: Color? = nil, fontSize: CGFloat? = nil, lineWidth: CGFloat? = nil, style: TextStyle? = nil) {
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

    func handleSelectionChange(to newId: UUID?) {
        guard let id = newId, let item = annotations.firstIndex(where: { $0.id == id }).map({ annotations[$0] }) else { return }

        selectedColor = item.color
        if item.type == .text || item.type == .numberedText || item.type == .rectText || item.type == .counter || (behavior.syncFontSizeForAiMarker && item.type == .aiMarker) {
            selectedFontSize = item.fontSize ?? 16.0
        } else if behavior.syncBrushSizeForBrushTools && (item.type == .highlighter || item.type == .blur || item.type == .mosaic) {
            selectedBrushSize = item.lineWidth
        } else {
            selectedLineWidth = item.lineWidth
        }
        if let style = item.fontStyle {
            selectedTextStyle = style
        }
    }

    // MARK: - 删除

    func deleteSelectedAnnotation() {
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

    // MARK: - 文本提交

    func commitTextEdit() {
        if let currentEditing = editingTextId {
            if let idx = annotations.firstIndex(where: { $0.id == currentEditing }) {
                if (annotations[idx].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if behavior.includeEmptyTextInUndo {
                        prepareForWrite()
                    }
                    annotations.remove(at: idx)
                } else {
                    let item = annotations[idx]
                    let fontSize = item.fontSize ?? 16.0
                    let singleLineHeight = fontSize * 1.2 + 16
                    if item.type != .rectText, item.customWidth == nil,
                       (item.text ?? "").contains("\n") || item.rect.height > singleLineHeight + 4 {
                        annotations[idx].customWidth = item.rect.width
                    }
                }
            }
        }
        if let currentEditingCounter = editingCounterId {
            if let idx = annotations.firstIndex(where: { $0.id == currentEditingCounter }) {
                let newStr = annotations[idx].customCounterString ?? ""
                reorderCounters(after: currentEditingCounter, newString: newStr)
            }
        }
        editingCounterId = nil
        editingTextId = nil
    }

    /// 点击空白处提交所有编辑态（counter / text）
    func commitAllEdits() {
        guard editingTextId != nil || editingCounterId != nil else { return }
        // 先处理数据与排序；编辑态 ID 清空后，AutoSizingTextView.updateNSView
        // 会检测到编辑态结束并安全地辞去 NSTextView 的第一响应者，
        // 避免在 async 通知路径中直接访问可能已释放的 responder。
        commitTextEdit()
    }

    // MARK: - 拖拽处理

    /// handleDragStart 的返回结果
    enum DragStartOutcome {
        case hitExistingAnnotation
        case hitEmpty
    }

    /// 处理拖拽开始：hitTest → 选中/双击进编辑
    /// - Parameters:
    ///   - point: 拖拽起点
    ///   - clickCount: 系统点击计数
    ///   - rectTextBounds: RectText 矩形框边界计算闭包
    ///   - isPointInNumberedCircle: 判断点是否在 NumberedText 圆圈内（ARV 独有，OW 传 nil）
    /// - Returns: 命中已有标注返回 .hitExistingAnnotation，否则返回 .hitEmpty
    func handleDragStart(
        _ point: CGPoint,
        clickCount: Int,
        rectTextBounds: (AnnotationItem) -> CGRect?,
        isPointInNumberedCircle: ((CGPoint, AnnotationItem) -> Bool)?
    ) -> DragStartOutcome {
        dragStartClickCount = clickCount
        dragStartPos = point
        lastDragPoint = point
        let now = ProcessInfo.processInfo.systemUptime
        let clickInterval = now - lastClickTime

        // 1. hitTest → 选中/双击进编辑
        if let (id, handle) = hitTestAnnotation(point: point, rectTextBounds: rectTextBounds) {
            // 如果点中其他元素，先统一提交当前编辑态
            if (editingTextId != nil && editingTextId != id) || (editingCounterId != nil && editingCounterId != id) {
                commitAllEdits()
            }
            prepareForWrite()
            selectedAnnotationId = id
            annotationActiveHandle = handle
            annotationInitialItem = annotations.first(where: { $0.id == id })
            annotationDragStartPoint = point

            // 双击进编辑（参数化检测策略）
            let isDoubleClick: Bool
            if behavior.trustClickCount {
                // ARV: 信任 clickCount + 时间间隔兜底
                isDoubleClick = clickCount >= 2 || (lastClickAnnotationId == id && clickInterval < behavior.doubleClickInterval)
            } else {
                // OW: 仅时间间隔，且 handle == nil
                isDoubleClick = handle == nil && lastClickAnnotationId == id && clickInterval < behavior.doubleClickInterval
            }

            if isDoubleClick {
                let item = annotations.first(where: { $0.id == id })
                // ARV 独有：检查 numberedText 圆圈进入 counter 编辑
                if behavior.trustClickCount, let item = item, item.type == .numberedText, isPointInNumberedCircle?(point, item) == true {
                    editingCounterId = id
                } else if item?.type == .text || item?.type == .numberedText || item?.type == .rectText {
                    editingTextId = id
                } else if item?.type == .counter {
                    editingCounterId = id
                }
            }
            lastClickTime = now
            lastClickAnnotationId = id
            return .hitExistingAnnotation
        }

        // 2. 未命中
        lastClickTime = now
        lastClickAnnotationId = nil
        return .hitEmpty
    }

    /// 创建新标注（调用前由 View 负责提交编辑态和清空选中）
    /// - Returns: 文本类工具返回新标注 ID（供 View 设置 selectedAnnotationId），其他工具返回 nil
    func createNewAnnotation(at point: CGPoint) -> UUID? {
        if selectedTool == .text || selectedTool == .numberedText {
            prepareForWrite()
            var cValue: Int? = nil
            if selectedTool == .numberedText {
                cValue = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
            }
            let textItem = AnnotationItem(type: selectedTool, startPoint: point, endPoint: point, color: selectedColor, lineWidth: 2.0, text: "", fontStyle: selectedTextStyle, fontSize: selectedFontSize, counterValue: cValue)
            annotations.append(textItem)
            editingTextId = textItem.id
            return textItem.id
        } else {
            if currentAnnotation == nil {
                prepareForWrite()
                var cValue: Int? = nil
                if selectedTool == .aiMarker {
                    cValue = annotations.filter { $0.type == .aiMarker }.count + 1
                } else if selectedTool == .counter || selectedTool == .numberedText {
                    cValue = annotations.filter { $0.type == .counter || $0.type == .numberedText }.count + 1
                }
                let markerColor = behavior.usePurpleForAiMarker && selectedTool == .aiMarker ? TMDesign.Colors.purple.opacity(0.7) : selectedColor
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
            return nil
        }
    }

    /// 处理拖拽过程：选中标注的拖拽/调整大小，或 freehand 标注的点追加
    /// - Parameters:
    ///   - point: 当前拖拽点
    ///   - boundsProvider: 画布边界闭包（ARV 返回固定大小，OW 返回 finalRect）
    func handleDragChange(_ point: CGPoint, boundsProvider: () -> CGRect?) {
        lastDragPoint = point
        let canvasBounds = boundsProvider()

        // 1. 选中标注的拖拽/调整大小
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
            annotations[index] = AnnotationGeometry.clampedAnnotation(updatedItem, to: canvasBounds)
            return
        }

        // 2. freehand 标注的点追加
        if selectedTool != .text {
            if var current = currentAnnotation, current.isFreehandTool {
                var clampedPoint = point
                if let bounds = canvasBounds, !bounds.isEmpty, !bounds.contains(point) {
                    clampedPoint = CGPoint(
                        x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY)
                    )
                }
                if current.points == nil { current.points = [] }
                if let lastPoint = current.points?.last {
                    let distance = hypot(clampedPoint.x - lastPoint.x, clampedPoint.y - lastPoint.y)
                    if distance > Self.brushDistanceThreshold {
                        current.points?.append(clampedPoint)
                        current.endPoint = clampedPoint
                    }
                } else {
                    current.points?.append(clampedPoint)
                    current.endPoint = clampedPoint
                }
                currentAnnotation = current
            } else if currentAnnotation?.type == .rectText {
                var clampedPoint = point
                if let bounds = canvasBounds, !bounds.isEmpty, !bounds.contains(point) {
                    clampedPoint = CGPoint(
                        x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY)
                    )
                }
                currentAnnotation?.points?[1] = clampedPoint
                currentAnnotation?.endPoint = clampedPoint
            } else {
                var clampedPoint = point
                if let bounds = canvasBounds, !bounds.isEmpty, !bounds.contains(point) {
                    clampedPoint = CGPoint(
                        x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY)
                    )
                }
                currentAnnotation?.endPoint = clampedPoint
            }
        }
    }

    /// 处理拖拽结束：双击进入编辑检测、选中标注清理、currentAnnotation 保存
    func handleDragEnd() {
        // 1. 双击进入编辑检测
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

        // 2. 选中标注拖拽结束清理
        if annotationInitialItem != nil {
            let changed = (undoStack.last != annotations)
            annotationInitialItem = nil
            annotationDragStartPoint = nil
            annotationActiveHandle = nil
            if !changed { if !undoStack.isEmpty { _ = undoStack.removeLast() } }
            return
        }

        // 3. currentAnnotation 保存逻辑
        if selectedTool != .text {
            if let final = currentAnnotation {
                var shouldSave = false
                if final.isFreehandTool {
                    if let points = final.points, points.count > 3 { annotations.append(final); shouldSave = true }
                } else {
                    let dx = abs(final.startPoint.x - final.endPoint.x)
                    let dy = abs(final.startPoint.y - final.endPoint.y)
                    // 参数化 aiMarker 保存条件
                    if final.type == .counter || (behavior.aiMarkerSaveOnClick && final.type == .aiMarker) || dx > 5 || dy > 5 {
                        annotations.append(final)
                        shouldSave = true
                    }
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
                    // 不设置 customWidth：rectText 文本框自动扩展到截图选区边缘，与正常文本框行为一致
                    selectedAnnotationId = annotations[idx].id
                    editingTextId = annotations[idx].id
                }
                if !shouldSave { if !undoStack.isEmpty { _ = undoStack.removeLast() } }
            }
            currentAnnotation = nil
        }
    }
}
