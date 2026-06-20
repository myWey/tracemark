import SwiftUI
import AppKit

public struct TranslationSidebarView: View {
    let sourceText: String
    @Binding var translatedText: String
    var isLoading: Bool
    var onClose: () -> Void
    var onRetranslate: () -> Void

    /// 随当前外观自动切换的轻量遮罩：白天用黑、夜间用白，保证文字始终清晰可读
    private var loadingOverlayColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)
        }))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("翻译结果")
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

            // Translated text section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("译文")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    CopyButton(text: translatedText)
                }

                ZStack(alignment: .center) {
                    ScrollView {
                        if translatedText.isEmpty {
                            Text("暂无译文")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                        } else {
                            SelectableTextView(text: translatedText, fontSize: 14, textColor: .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Loading 指示器居中显示，避免全屏遮罩压暗译文
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                            Text("翻译中...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(loadingOverlayColor)
                        )
                    }
                }
            }
            .padding(12)
            // 使用 textBackgroundColor 替代低透明度 secondary，确保白天/夜间都有足够对比度
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Footer
            HStack(spacing: 12) {
                Button(action: onRetranslate) {
                    HStack(spacing: 4) {
                        Image(systemName: sfSymbol("translate", fallback: "globe"))
                        Text("重新翻译")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)

                Spacer()

                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                        Text("收起")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: 320, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// 支持鼠标拖拽选择、Cmd+C 复制的只读文本视图
private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: Color

    func makeNSView(context: Context) -> AutoResizingNSTextView {
        let textView = AutoResizingNSTextView()
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = NSColor(textColor).usingColorSpace(.sRGB) ?? NSColor(textColor)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.focusRingType = .none
        textView.drawsBackground = false
        textView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.autoresizingMask = [.width]
        textView.string = text
        return textView
    }

    func updateNSView(_ nsView: AutoResizingNSTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
        }
        nsView.font = .systemFont(ofSize: fontSize)
        nsView.textColor = NSColor(textColor).usingColorSpace(.sRGB) ?? NSColor(textColor)
        nsView.invalidateIntrinsicContentSize()
    }
}

private struct CopyButton: View {
    let text: String
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
                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(showCopiedFeedback ? "已复制" : "复制")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(text.isEmpty)
    }
}
