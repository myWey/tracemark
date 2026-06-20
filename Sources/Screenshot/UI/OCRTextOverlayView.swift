import SwiftUI
import AppKit

public extension Notification.Name {
    /// OCR 图像层字符级选中状态发生变化。
    /// userInfo 包含：
    /// - "selectedBlockId": UUID?（当前主要选中的识别块）
    /// - "selectedChars": [UUID: Set<Int>]（每个识别块被选中的字符索引）
    static let ocrSelectionChanged = Notification.Name("OCRSelectionChanged")
}

/// 在图片上方叠加可选择的 OCR 文本层。
/// 不再使用 NSTextView 的字体布局，而是直接基于 Vision 返回的字符级 bounding box 做命中检测，
/// 自定义绘制半透明高亮，保证复制内容与视觉上选中的字符完全一致。
public struct OCRTextOverlayView: NSViewRepresentable {
    public let textBlocks: [RecognizedTextBlock]
    public let displaySize: CGSize
    @Binding public var selectedBlockId: UUID?

    public init(textBlocks: [RecognizedTextBlock], displaySize: CGSize, selectedBlockId: Binding<UUID?>) {
        self.textBlocks = textBlocks
        self.displaySize = displaySize
        self._selectedBlockId = selectedBlockId
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(binding: $selectedBlockId)
    }

    public func makeNSView(context: Context) -> OCRTextOverlayNSView {
        let view = OCRTextOverlayNSView()
        view.displaySize = displaySize
        view.textBlocks = textBlocks
        let coordinator = context.coordinator
        view.onSelectionChanged = { [weak coordinator] id in
            coordinator?.binding.wrappedValue = id
        }
        return view
    }

    public func updateNSView(_ nsView: OCRTextOverlayNSView, context: Context) {
        nsView.displaySize = displaySize
        nsView.textBlocks = textBlocks
        let coordinator = context.coordinator
        nsView.onSelectionChanged = { [weak coordinator] id in
            coordinator?.binding.wrappedValue = id
        }
        if nsView.selectedBlockId != selectedBlockId {
            nsView.syncSelection(to: selectedBlockId)
        }
    }

    public class Coordinator: NSObject {
        var binding: Binding<UUID?>
        init(binding: Binding<UUID?>) {
            self.binding = binding
        }
    }
}

/// 承载 OCR 选择层的容器视图。
/// 负责根据鼠标拖拽计算字符级选中状态，并绘制高亮。
public class OCRTextOverlayNSView: NSView {
    var textBlocks: [RecognizedTextBlock] = [] {
        didSet { rebuildCharData() }
    }

    var displaySize: CGSize = .zero {
        didSet { rebuildCharData() }
    }

    var onSelectionChanged: ((UUID?) -> Void)?
    private(set) var selectedBlockId: UUID?

    /// 每个字符的视图坐标 rect，索引与 block.text 的字符索引对应
    private var charRects: [UUID: [CGRect]] = [:]
    /// 选中状态：block id -> 选中的字符索引集合
    private var selectedChars: [UUID: Set<Int>] = [:]

    private var dragStartPoint: NSPoint?
    private var dragCurrentPoint: NSPoint?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { return true }
    public override var isFlipped: Bool { return true }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: NSCursor.iBeam)
    }

    func syncSelection(to id: UUID?) {
        selectedBlockId = id
        selectedChars.removeAll()
        if let id = id, let block = textBlocks.first(where: { $0.id == id }) {
            selectedChars[id] = Set(0..<block.text.count)
        }
        onSelectionChanged?(id)
        postSelectionChangedNotification()
        needsDisplay = true
    }

    private func rebuildCharData() {
        guard displaySize.width > 0, displaySize.height > 0 else {
            charRects.removeAll()
            selectedChars.removeAll()
            return
        }

        var newCharRects: [UUID: [CGRect]] = [:]
        for block in textBlocks {
            let rects = block.charRectsInView(size: displaySize)
            newCharRects[block.id] = rects
        }
        charRects = newCharRects

        // 过滤掉已不存在的 block 的选中状态
        let validIds = Set(textBlocks.map(\.id))
        selectedChars = selectedChars.filter { validIds.contains($0.key) }
        needsDisplay = true
    }

    private func selectionRect() -> CGRect? {
        guard let start = dragStartPoint, let current = dragCurrentPoint else { return nil }
        let minX = min(start.x, current.x)
        let maxX = max(start.x, current.x)
        let minY = min(start.y, current.y)
        let maxY = max(start.y, current.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func updateSelectionFromDrag() {
        guard let rect = selectionRect() else { return }

        var changed = false
        var newSelectedChars: [UUID: Set<Int>] = [:]
        var newSelectedBlockId: UUID?

        for block in textBlocks {
            guard let rects = charRects[block.id] else { continue }
            var selectedIndices = Set<Int>()
            for (index, charRect) in rects.enumerated() {
                // 使用矩形相交命中，提高拖扫灵敏度；即使只擦到字符边缘也能选中
                if rect.intersects(charRect) {
                    selectedIndices.insert(index)
                }
            }
            if !selectedIndices.isEmpty {
                newSelectedChars[block.id] = selectedIndices
                newSelectedBlockId = block.id
            }
        }

        if selectedChars != newSelectedChars {
            selectedChars = newSelectedChars
            selectedBlockId = newSelectedBlockId
            onSelectionChanged?(newSelectedBlockId)
            postSelectionChangedNotification()
            changed = true
        }

        if changed {
            needsDisplay = true
        }
    }

    private func postSelectionChangedNotification() {
        NotificationCenter.default.post(
            name: .ocrSelectionChanged,
            object: nil,
            userInfo: [
                "selectedBlockId": selectedBlockId as Any,
                "selectedChars": selectedChars
            ]
        )
    }

    private func copySelectedText() {
        guard !selectedChars.isEmpty else { return }

        // 按 block 在图像中的位置排序：从上到下，从左到右
        let sortedBlocks = textBlocks
            .filter { selectedChars[$0.id] != nil }
            .sorted { a, b in
                let rectA = a.rectInView(size: displaySize)
                let rectB = b.rectInView(size: displaySize)
                if abs(rectA.minY - rectB.minY) > 4 {
                    return rectA.minY < rectB.minY
                }
                return rectA.minX < rectB.minX
            }

        var pieces: [String] = []
        for block in sortedBlocks {
            guard let indices = selectedChars[block.id] else { continue }
            let chars = Array(block.text)
            let selected = indices.sorted().compactMap { index in
                chars.indices.contains(index) ? String(chars[index]) : nil
            }
            pieces.append(selected.joined())
        }

        let text = pieces.joined(separator: "\n")
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        // 双击选中整个识别块
        if event.clickCount == 2 {
            for block in textBlocks {
                let blockRect = block.rectInView(size: displaySize)
                if blockRect.contains(point) {
                    selectedChars = [block.id: Set(0..<block.text.count)]
                    selectedBlockId = block.id
                    onSelectionChanged?(block.id)
                    postSelectionChangedNotification()
                    needsDisplay = true
                    dragStartPoint = nil
                    dragCurrentPoint = nil
                    return
                }
            }
        }

        dragStartPoint = point
        dragCurrentPoint = point

        // 暂不立刻清除选择，给用户拖拽选中的连续感；
        // 如果这次没有选中任何字符，mouseUp 时再清空。
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragCurrentPoint = point
        updateSelectionFromDrag()
    }

    public override func mouseUp(with event: NSEvent) {
        updateSelectionFromDrag()
        dragStartPoint = nil
        dragCurrentPoint = nil
        needsDisplay = true

        // 如果拖拽后没有任何字符被选中，清空选中状态
        if selectedChars.isEmpty {
            selectedBlockId = nil
            onSelectionChanged?(nil)
            postSelectionChangedNotification()
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.keyCode == 8 { // Cmd+C
            copySelectedText()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let highlightColor = NSColor.systemBlue.withAlphaComponent(0.25)
        ctx.setFillColor(highlightColor.cgColor)

        for (blockId, indices) in selectedChars {
            guard let rects = charRects[blockId] else { continue }
            let sortedIndices = indices.sorted()
            var mergedRects: [CGRect] = []

            for index in sortedIndices {
                guard rects.indices.contains(index) else { continue }
                let rect = rects[index]
                if let last = mergedRects.last, last.intersects(rect) {
                    mergedRects[mergedRects.count - 1] = last.union(rect)
                } else {
                    mergedRects.append(rect)
                }
            }

            for rect in mergedRects {
                ctx.fill(rect)
            }
        }
    }
}
