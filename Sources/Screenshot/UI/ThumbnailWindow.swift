import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// 悬浮缩略图窗口控制器
public class ThumbnailWindowController {
    public static let shared = ThumbnailWindowController()
    private var window: NSPanel?
    private var dismissTimer: Timer?
    
    private init() {}
    
    /// 在右下角淡入显示悬浮缩略图
    public func show(imageURL: URL, image: CGImage) {
        dismissTimer?.invalidate()
        window?.orderOut(nil)
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        
        // 缩略图卡片大小
        let cardWidth: CGFloat = 220
        let cardHeight: CGFloat = 150
        
        // 坐标计算：放置在屏幕右下角（留出 padding 20pt）
        let x = screenFrame.maxX - cardWidth - 20
        let y = screenFrame.minY + 20
        let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
        
        let rootView = ThumbnailRootView(
            imageURL: imageURL,
            image: image,
            onClose: {
                self.dismissWithAnimation()
            },
            onUserHover: { isHovering in
                if isHovering {
                    // 用户悬停时停止自动隐藏定时器
                    self.dismissTimer?.invalidate()
                } else {
                    // 移开后重新启动 3s 倒计时
                    self.startTimer(imageURL: imageURL)
                }
            }
        )
        let hostingView = TrackingHostingView(rootView: rootView.applyAppLanguage())
        hostingView.frame = NSRect(origin: .zero, size: rect.size)
        
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // 由 SwiftUI 卡片自绘阴影以实现极致圆角和软阴影
        panel.level = .floating
        panel.ignoresMouseEvents = false
        
        // 淡入动画显示
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1.0
        }
        
        self.window = panel
        
        // 启动 5s 自动销毁定时器
        startTimer(imageURL: imageURL)
    }
    
    private func startTimer(imageURL: URL) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            // 定时器触发：自动保存至默认位置（其实此时已经保存了，临时文件已在磁盘上）
            // 我们只需要把文件搬运至正式保存目录（例如 ~/Downloads），如果它还没有被搬过去的话。
            // 这里我们只是淡出缩略图窗口
            self.dismissWithAnimation()
        }
    }
    
    public func dismissWithAnimation() {
        dismissTimer?.invalidate()
        guard let panel = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
            self.window = nil
        })
    }
}

/// 悬浮缩略图卡片 SwiftUI 视图
struct ThumbnailRootView: View {
    let imageURL: URL
    let image: CGImage
    let onClose: () -> Void
    let onUserHover: (Bool) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 1. 卡片主体
            ZStack {
                // 截图缩略图背景
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle()) // 确保整块区域可点击
                    .onTapGesture {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenAnnotationCanvas"), object: nil, userInfo: ["image": image])
                        onClose()
                    }
                
                // 悬浮在上面的磨砂动作按钮栏（仅在 Hover 时显现）
                if isHovering {
                    Color.black.opacity(0.25)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                    
                    HStack(spacing: 16) {
                        // 标注编辑按钮
                        ActionButton(icon: "paintbrush.fill", tooltip: "进入标注与涂抹") {
                            NotificationCenter.default.post(name: NSNotification.Name("OpenAnnotationCanvas"), object: nil, userInfo: ["image": image])
                            onClose()
                        }
                        
                        // 复制按钮
                        ActionButton(icon: "doc.on.doc.fill", tooltip: "复制到剪贴板") {
                            copyToClipboard()
                            onClose()
                        }
                        
                        // 保存按钮
                        ActionButton(icon: "square.and.arrow.down.fill", tooltip: "保存到下载") {
                            saveToDownloads()
                            onClose()
                        }
                    }
                    .transition(.scale)
                }
            }
            // 提供 macOS 完美的拖拽导出文件能力！
            .onDrag {
                onUserHover(true) // 拖拽时取消 dismiss timer
                return NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .padding(10) // 留白给外层阴影
            
            // 2. 右上角的小关闭按钮（仅在 Hover 时显现）
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .background(Color.white.clipShape(Circle()))
                }
                .buttonStyle(ScaleButtonStyle())
                .offset(x: -2, y: 2)
                .transition(.opacity)
            }
        }
        .frame(width: 220, height: 150)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            onUserHover(hovering)
        }
    }
    
    /// 动作方法：复制到剪贴板
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let pbItem = NSPasteboardItem()
        if let pngData = CaptureEngine.shared.pngData(from: image) {
            pbItem.setData(pngData, forType: .png)
            pasteboard.writeObjects([pbItem])
        } else {
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            pasteboard.writeObjects([nsImage])
        }
        print("📋 [ThumbnailView] 已复制到系统剪贴板")
    }
    
    /// 动作方法：主动转存到 ~/Downloads 目录
    private func saveToDownloads() {
        let fileManager = FileManager.default
        let downloadsDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destURL = downloadsDir.appendingPathComponent(imageURL.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: imageURL, to: destURL)
            print("💾 [ThumbnailView] 成功复制截图到下载目录: \(destURL.path)")
        } catch {
            print("❌ [ThumbnailView] 保存到下载目录失败: \(error)")
        }
    }
}

/// 悬浮态缩放效果按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 精美圆型动作按钮
struct ActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.85))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .help(tooltip)
    }
}
