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
}
