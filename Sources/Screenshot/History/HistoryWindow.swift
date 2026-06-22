import Cocoa
import SwiftUI

public class HistoryWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = HistoryWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dashboard"
        window.center()
        window.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: DashboardRootView().applyAppLanguage())
        window.contentView = hostingView
        
        super.init(window: window)
        window.delegate = self
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowWillClose(_ notification: Notification) {
        // 仅当标注窗口也不可见时才恢复 .accessory，避免影响标注窗口的 IME 文本输入
        if !AnnotationManager.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
