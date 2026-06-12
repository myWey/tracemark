import Cocoa
import Carbon

public class HotkeyManager {
    public static let shared = HotkeyManager()
    private var callback: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var isEventHandlerInstalled = false
    
    public var currentKeyCode: UInt16 = 0
    public var currentModifiers: UInt32 = UInt32(cmdKey | controlKey)
    
    private init() {
        loadFromUserDefaults()
    }
    
    public func register(callback: @escaping () -> Void) {
        self.callback = callback
        installEventHandlerIfNeeded()
        _ = registerCurrentShortcut()
    }
    
    public func updateShortcut(keyCode: UInt16, modifiers: UInt32) -> Bool {
        let oldKeyCode = currentKeyCode
        let oldModifiers = currentModifiers
        
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers
        
        if registerCurrentShortcut() {
            saveToUserDefaults()
            return true
        } else {
            // Rollback on failure
            self.currentKeyCode = oldKeyCode
            self.currentModifiers = oldModifiers
            _ = registerCurrentShortcut()
            return false
        }
    }
    
    private func installEventHandlerIfNeeded() {
        guard !isEventHandlerInstalled else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerUPP: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            HotkeyManager.shared.handleHotkeyTriggered()
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            nil,
            nil
        )
        
        if status != noErr {
            print("❌ [HotkeyManager] 挂载事件处理器失败: \(status)")
        } else {
            isEventHandlerInstalled = true
        }
    }
    
    private func registerCurrentShortcut() -> Bool {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(signature: OSType(1397048147), id: 1) // 'SCRN'
        var hotKey: EventHotKeyRef?
        
        let regStatus = RegisterEventHotKey(
            UInt32(currentKeyCode),
            currentModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        
        if regStatus != noErr {
            print("❌ [HotkeyManager] 注册全局快捷键失败, 错误码: \(regStatus)")
            return false
        } else {
            self.hotKeyRef = hotKey
            print("✅ [HotkeyManager] 成功注册全局快捷键")
            return true
        }
    }
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(Int(currentKeyCode), forKey: "Hotkey_KeyCode")
        UserDefaults.standard.set(Int(currentModifiers), forKey: "Hotkey_Modifiers")
    }
    
    private func loadFromUserDefaults() {
        if UserDefaults.standard.object(forKey: "Hotkey_KeyCode") != nil {
            currentKeyCode = UInt16(UserDefaults.standard.integer(forKey: "Hotkey_KeyCode"))
            currentModifiers = UInt32(UserDefaults.standard.integer(forKey: "Hotkey_Modifiers"))
        }
    }
    
    private func handleHotkeyTriggered() {
        print("🔔 [HotkeyManager] 全局快捷键被触发")
        DispatchQueue.main.async {
            self.callback?()
        }
    }
}
