import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// 注意：入口已迁移至 main.swift（纯 AppKit 生命周期）


class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 激活策略已在 main.swift 中设置为 .accessory
        
        // 0. 仅在首次启动时主动弹窗请求系统权限（避免后续重启时因为拒绝过而反复弹窗）
        if !UserDefaults.standard.bool(forKey: "HasPromptedPermissionsOnLaunch") {
            if #available(macOS 11.0, *) {
                CGRequestScreenCaptureAccess()
            }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            UserDefaults.standard.set(true, forKey: "HasPromptedPermissionsOnLaunch")
        }
        
        // 初始化标注管理器以注册通知监听
        _ = AnnotationManager.shared
        
        // 1. 创建状态栏图标与菜单
        setupStatusItem()
        
        // 2. 注册全局快捷键 Control + Command + A
        HotkeyManager.shared.register { [weak self] in
            self?.triggerCapture()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenu), name: NSNotification.Name("LanguageDidChange"), object: nil)
        
        print("🚀 [AppDelegate] TraceMark 启动成功，驻留后台菜单栏...")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // 当应用被激活时（如通过 Cmd+Tab），将所有可见的辅助窗口（如历史记录、标注窗口、贴图等）置于最前
        for window in NSApp.windows {
            if window.isVisible && !(window is CaptureOverlayWindow) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            HistoryWindowController.shared.show()
        } else {
            for window in NSApp.windows {
                if window is NSPanel && window.isVisible && !(window is CaptureOverlayWindow) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        return true
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // 设置状态栏图标（使用系统 SF Symbols）
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "截图")?
            .withSymbolConfiguration(config) {
            button.image = image
        } else {
            button.title = "📸"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        updateMenu()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
    }
    
    @objc private func updateMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        
        let lm = LanguageManager.shared
        
        let shortcutStr = UserDefaults.standard.string(forKey: "captureShortcut") ?? "Option + A"
        let captureTitle = "\(lm.localizedString(forKey: "区域截图")) (\(shortcutStr))"
        let captureItem = NSMenuItem(title: captureTitle, action: #selector(triggerCaptureAction), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closePinsItem = NSMenuItem(title: lm.localizedString(forKey: "关闭所有贴图"), action: #selector(closeAllPinsAction), keyEquivalent: "")
        closePinsItem.target = self
        menu.addItem(closePinsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let historyItem = NSMenuItem(title: lm.localizedString(forKey: "历史记录"), action: #selector(showHistoryAction), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
        
        let preferencesItem = NSMenuItem(title: lm.localizedString(forKey: "偏好设置"), action: #selector(showPreferencesAction), keyEquivalent: "")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: lm.localizedString(forKey: "退出"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func triggerCaptureAction() {
        triggerCapture()
    }
    
    @objc private func closeAllPinsAction() {
        PinManager.shared.closeAll()
    }
    
    @objc private func showHistoryAction() {
        if isCapturing {
            OverlayManager.shared.closeAll()
            isCapturing = false
        }
        DashboardRouter.shared.selectedTab = .history
        HistoryWindowController.shared.show()
    }
    
    @objc private func showPreferencesAction() {
        if isCapturing {
            OverlayManager.shared.closeAll()
            isCapturing = false
        }
        DashboardRouter.shared.selectedTab = .preferences
        HistoryWindowController.shared.show()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private var isCapturing = false
    
    /// 触发整个截图核心工作流
    private func triggerCapture() {
        if isCapturing {
            print("⚠️ [AppDelegate] 正在收集中，取消旧任务并重新开始")
            OverlayManager.shared.closeAll()
            isCapturing = false
            
            // 给旧窗口销毁留出极小的时间窗口，避免被截取进新截图
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.triggerCapture()
            }
            return
        }
        isCapturing = true
        
        print("📸 [AppDelegate] 触发截图捕获...")
        
        // 1. 抓取所有屏幕 (必须在 activate 之前执行，否则台前调度模式下会清屏)
        let captures = CaptureEngine.shared.captureAllScreens()
        print("ℹ️ [AppDelegate] 捕获到 \(captures.count) 个屏幕快照")
        if captures.isEmpty {
            print("❌ [AppDelegate] 未能捕获任何屏幕画面，截屏流程终止")
            isCapturing = false
            return
        }
        
        // 抓取完成后，不需要强行激活应用，只将遮罩提升到最前即可避免主屏幕空间切换 (P3)
        
        // 2. 唤起全屏半透明选区遮罩
        print("ℹ️ [AppDelegate] 准备唤起 OverlayManager 遮罩层...")
        OverlayManager.shared.showOverlay(captures: captures) { [weak self] croppedImage, cleanImage, annotations, screen, action in
            self?.isCapturing = false
            print("✅ [AppDelegate] 收到截图裁剪结果回调")
            self?.handleCapturedImage(croppedImage, cleanImage: cleanImage, annotations: annotations, screen: screen, action: action)
        } canceled: { [weak self] in
            self?.isCapturing = false
            print("ℹ️ [AppDelegate] 收到截图取消回调")
        }
    }
    
    /// 处理截图完成后的图像
    private func handleCapturedImage(_ image: CGImage, cleanImage: CGImage? = nil, annotations: [AnnotationItem]? = nil, screen: NSScreen, action: PostCaptureAction = .none) {
        // 保存一份正本到本地历史
        CaptureEngine.shared.saveToDisk(image: image, originalImage: cleanImage, annotations: annotations)
        
        // 复制到剪贴板
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        
        print("✅ [AppDelegate] 最终截图已保存并复制到剪贴板！")
        
        if action == .none {
            DispatchQueue.main.async {
                ToastManager.shared.showToast(message: LanguageManager.shared.localizedString(forKey: "截图已复制并保存至历史记录"))
            }
        }
        
        if action != .none {
            let recordId = HistoryManager.shared.records.first?.id
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenAnnotationCanvas"),
                    object: nil,
                    userInfo: [
                        "image": image,
                        "annotations": annotations ?? [],
                        "recordId": recordId as Any
                    ]
                )
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: NSNotification.Name("TriggerPostCaptureAction"), object: action)
            }
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeAllPinsAction) {
            return PinManager.shared.hasPins
        }
        return true
    }
}
