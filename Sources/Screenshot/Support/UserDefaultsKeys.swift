import Foundation

/// UserDefaults 键名常量
enum UserDefaultsKey {
    // 权限提示
    static let hasPromptedPermissionsOnLaunch = "HasPromptedPermissionsOnLaunch"
    // 快捷键
    static let hotkeyKeyCode = "Hotkey_KeyCode"
    static let hotkeyModifiers = "Hotkey_Modifiers"
    // 截图快捷键（PreferencesView 自定义）
    static let captureShortcut = "captureShortcut"
    // 语言选择
    static let appLanguageSelection = "AppLanguageSelection"
}
