import Cocoa

// 纯 AppKit 入口：绕过 SwiftUI App 生命周期，确保手动创建的 NSWindow/NSPanel
// 能正确被 macOS 窗口管理器渲染。这是 macOS 菜单栏工具的标准做法。
// 确保单实例运行，杀掉旧的 TraceMark 进程
let runningApps = NSWorkspace.shared.runningApplications
for runningApp in runningApps {
    if runningApp.localizedName == "TraceMark" && runningApp != NSRunningApplication.current {
        AppLogger.app.warning("⚠️ [main] 发现旧版 TraceMark 进程 (PID: \(runningApp.processIdentifier))，正在终止...")
        runningApp.forceTerminate()
    }
}

let app = NSApplication.shared

// 创建主菜单以拦截快捷键（避免按 Cmd+Z 等时系统发出嘟嘟声）
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)

let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
editMenu.addItem(NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z"))
editMenu.addItem(NSMenuItem.separator())
editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{0008}"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
