import SwiftUI

fileprivate func localized(_ key: String) -> String {
    LanguageManager.shared.localizedString(forKey: key)
}

public struct OCRResultPanel: View {
    @Binding var text: String
    let textBlocks: [RecognizedTextBlock]
    let imageSize: CGSize
    @Binding var selectedBlockId: UUID?
    var onClose: () -> Void

    /// 图像层当前选中的字符索引，按识别块分组
    @State private var selectedChars: [UUID: Set<Int>] = [:]
    /// 用于 ScrollViewReader 自动滚动到选中识别块
    @State private var scrollTarget: UUID? = nil
    /// 通知监听 token，用于 onDisappear 清理
    @State private var selectionObserver: NSObjectProtocol?

    @ObservedObject private var languageManager = LanguageManager.shared

    public init(
        text: Binding<String>,
        textBlocks: [RecognizedTextBlock] = [],
        imageSize: CGSize = .zero,
        selectedBlockId: Binding<UUID?> = .constant(nil),
        onClose: @escaping () -> Void
    ) {
        self._text = text
        self.textBlocks = textBlocks
        self.imageSize = imageSize
        self._selectedBlockId = selectedBlockId
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(localized("OCR_Recognized_Text"))
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            // 识别块列表：文字 + 坐标，支持字符级高亮联动与文本选择复制
            if !textBlocks.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(textBlocks.enumerated()), id: \.element.id) { index, block in
                                BlockRow(
                                    index: index,
                                    block: block,
                                    pixelRect: pixelRect(for: block),
                                    isSelected: selectedBlockId == block.id,
                                    selectedIndices: selectedChars[block.id] ?? [],
                                    onTap: {
                                        selectedBlockId = block.id
                                        scrollTarget = block.id
                                    }
                                )
                                .id(block.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: scrollTarget) { target in
                        if let target = target {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // 批量复制按钮
                HStack(spacing: 12) {
                    Spacer()

                    CopyFeedbackButton(text: text, label: localized("OCR_Copy_Plain_Text"))

                    CopyFeedbackButton(
                        text: structuredText,
                        label: localized("OCR_Copy_Full_Info")
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Spacer()
                Text(localized("OCR_No_Results"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(width: 320, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            registerSelectionObserver()
        }
        .onDisappear {
            if let observer = selectionObserver {
                NotificationCenter.default.removeObserver(observer)
                selectionObserver = nil
            }
        }
        .onChange(of: selectedBlockId) { newId in
            if let id = newId {
                scrollTarget = id
            }
        }
    }

    private func registerSelectionObserver() {
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .ocrSelectionChanged,
            object: nil,
            queue: .main
        ) { notification in
            let blockId = notification.userInfo?["selectedBlockId"] as? UUID
            let chars = notification.userInfo?["selectedChars"] as? [UUID: Set<Int>] ?? [:]
            self.selectedBlockId = blockId
            self.selectedChars = chars

            // 自动滚动到主要选中的识别块
            if let id = blockId, id != self.scrollTarget {
                self.scrollTarget = id
            }
        }
    }

    /// 将 Vision 归一化坐标转换为以左上角为原点的像素坐标
    private func pixelRect(for block: RecognizedTextBlock) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return block.boundingBox }
        let width = imageSize.width
        let height = imageSize.height
        let pixelX = block.boundingBox.minX * width
        let pixelY = (1.0 - block.boundingBox.maxY) * height
        let pixelWidth = block.boundingBox.width * width
        let pixelHeight = block.boundingBox.height * height
        return CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
    }

    /// 带坐标的结构化全文，用于"复制完整信息"
    private var structuredText: String {
        textBlocks.enumerated().map { index, block in
            let rect = pixelRect(for: block)
            let coord = "[\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.maxX)), \(Int(rect.maxY))]"
            return "\(index + 1). \(coord) \(block.text)"
        }.joined(separator: "\n")
    }
}

// MARK: - 单个识别块行

private struct BlockRow: View {
    let index: Int
    let block: RecognizedTextBlock
    let pixelRect: CGRect
    let isSelected: Bool
    let selectedIndices: Set<Int>
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.purple.opacity(0.8))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HighlightedText(
                    text: block.text,
                    selectedIndices: selectedIndices
                )
                .font(.system(size: 13))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

                Text(coordString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 4)

            BlockCopyButton(
                text: "\(coordString) \(block.text)",
                tooltip: localized("OCR_Copy_Full_Info_Tooltip")
            )
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.06))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var coordString: String {
        "[\(Int(pixelRect.minX)), \(Int(pixelRect.minY)), \(Int(pixelRect.maxX)), \(Int(pixelRect.maxY))]"
    }
}

// MARK: - 字符级高亮文本

private struct HighlightedText: View {
    let text: String
    let selectedIndices: Set<Int>

    var body: some View {
        Text(attributedString)
            .foregroundColor(.primary)
    }

    private var attributedString: AttributedString {
        let attr = NSMutableAttributedString(string: text)
        let highlightColor = NSColor.systemBlue.withAlphaComponent(0.3)
        for index in selectedIndices {
            guard index >= 0, index < text.count else { continue }
            let nsRange = NSRange(location: index, length: 1)
            attr.addAttribute(.backgroundColor, value: highlightColor, range: nsRange)
        }
        return AttributedString(attr)
    }
}

// MARK: - 复制按钮

private struct BlockCopyButton: View {
    let text: String
    let tooltip: String
    @State private var showCopiedFeedback: Bool = false

    var body: some View {
        Button(action: {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            withAnimation(.spring()) {
                showCopiedFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring()) {
                    showCopiedFeedback = false
                }
            }
        }) {
            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showCopiedFeedback ? .green : .secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
    }
}

private struct CopyFeedbackButton: View {
    let text: String
    let label: String
    @State private var showCopiedFeedback: Bool = false

    var body: some View {
        Button(action: {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            withAnimation(.spring()) {
                showCopiedFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring()) {
                    showCopiedFeedback = false
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .medium))
                Text(showCopiedFeedback ? localized("OCR_Copied") : label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(showCopiedFeedback ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(text.isEmpty)
    }
}
