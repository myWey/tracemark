import SwiftUI
import CoreGraphics

/// 标注编辑共享 ViewModel
/// 持有两个 RootView（AnnotationRootView + OverlayRootView）的共享标注编辑状态与方法，
/// 消除重复代码。行为差异通过 Behavior 配置参数化。
@MainActor
final class AnnotationEditViewModel: ObservableObject {

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

        /// AnnotationRootView 行为配置
        static let annotationConfig = Behavior(
            aiMarkerSaveOnClick: true,
            doubleClickInterval: 0.5,
            trustClickCount: true,
            syncFontSizeForAiMarker: true,
            syncBrushSizeForBrushTools: false,
            includeEmptyTextInUndo: false,
            cornerMinHitZone: 10,
            edgeHitZone: nil
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
            edgeHitZone: 20
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
                    if item.customWidth == nil,
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
}
