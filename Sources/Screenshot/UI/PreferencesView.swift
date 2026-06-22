import SwiftUI
import Carbon
import ServiceManagement

public struct PreferencesView: View {
    @State private var isRecording = false
    @State private var recordedShortcut: String = "Option + A"
    @State private var showConflictToast = false
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    /// AI 定位复制坐标话术：存储用户自定义值，空字符串表示回退到 i18n 默认
    @AppStorage(UserDefaultsKey.aiMarkerCoordsTemplate) private var coordsTemplateRaw: String = ""
    
    /// 对外暴露的话术：raw 为空时回退到当前语言的本地化默认值
    private var coordsTemplate: Binding<String> {
        Binding(
            get: {
                coordsTemplateRaw.isEmpty
                    ? LanguageManager.shared.localizedString(forKey: "aiMarker.coordsTemplate")
                    : coordsTemplateRaw
            },
            set: { newValue in
                // 纯空白视为空，回退到 i18n 默认话术
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                coordsTemplateRaw = trimmed
            }
        )
    }
    
    public init() {
        let code = HotkeyManager.shared.currentKeyCode
        let mod = HotkeyManager.shared.currentModifiers
        
        var shortcutStr = ""
        if (mod & UInt32(controlKey)) != 0 { shortcutStr += "Control + " }
        if (mod & UInt32(optionKey)) != 0 { shortcutStr += "Option + " }
        if (mod & UInt32(shiftKey)) != 0 { shortcutStr += "Shift + " }
        if (mod & UInt32(cmdKey)) != 0 { shortcutStr += "Command + " }
        
        // simple fallback for A (0)
        let key = (code == 0) ? "A" : "Key(\(code))"
        shortcutStr += key
        
        self._recordedShortcut = State(initialValue: shortcutStr)
    }
    
    public var body: some View {
        Form {
            // MARK: - 全局快捷键
            Section {
                HStack {
                    Text(LanguageManager.shared.localizedString(forKey: "截图快捷键:"))
                    Spacer()
                    Button(action: { isRecording = true }) {
                        Text(isRecording
                             ? LanguageManager.shared.localizedString(forKey: "请按下新快捷键...")
                             : recordedShortcut)
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.bordered)
                    .tint(isRecording ? .red : .accentColor)
                    .background(
                        ShortcutRecorder(isRecording: $isRecording, currentShortcut: $recordedShortcut, onConflict: {
                            showConflictToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showConflictToast = false
                            }
                        })
                        .frame(width: 0, height: 0)
                    )
                }
            } header: {
                Text(LanguageManager.shared.localizedString(forKey: "全局快捷键"))
            } footer: {
                if showConflictToast {
                    Text(LanguageManager.shared.localizedString(forKey: "快捷键冲突或无效，请尝试其他组合。"))
                        .foregroundColor(.red)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.shared.localizedString(forKey: "点击上方按钮后直接按下组合键即可设置。"))
                        Text(LanguageManager.shared.localizedString(forKey: "注意：部分快捷键（如 Cmd+Space）被 macOS 系统全局保留，录制时若无反应请更换组合。"))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // MARK: - 常规设置
            Section {
                Toggle(LanguageManager.shared.localizedString(forKey: "开机自动启动"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            AppLogger.ui.error("Failed to update SMAppService: \(String(describing: error))")
                        }
                    }
                ))
            } header: {
                Text(LanguageManager.shared.localizedString(forKey: "常规设置"))
            }
            
            // MARK: - AI 定位话术
            Section {
                TextEditor(text: coordsTemplate)
                    .frame(minHeight: 64, idealHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                HStack {
                    Spacer()
                    Button(action: { coordsTemplateRaw = "" }) {
                        Text(LanguageManager.shared.localizedString(forKey: "恢复默认"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordsTemplateRaw.isEmpty)
                }
            } header: {
                Text(LanguageManager.shared.localizedString(forKey: "aiMarker.coordsTemplateSettingTitle"))
            } footer: {
                Text(LanguageManager.shared.localizedString(forKey: "aiMarker.coordsTemplateSettingDesc"))
            }
            
            // MARK: - 多语言
            Section {
                Picker(LanguageManager.shared.localizedString(forKey: "显示语言:"), selection: $languageManager.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(LanguageManager.shared.localizedString(forKey: "多语言支持"))
            } footer: {
                Text(LanguageManager.shared.localizedString(forKey: "TraceMark 默认跟随您的 macOS 系统语言。支持实时切换多种语言。"))
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var currentShortcut: String
    var onConflict: () -> Void
    
    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, RecorderNSViewDelegate {
        var parent: ShortcutRecorder
        
        init(_ parent: ShortcutRecorder) {
            self.parent = parent
        }
        
        func didRecord(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
            let carbonModifiers = carbonModifiers(from: modifiers)
            
            let success = HotkeyManager.shared.updateShortcut(keyCode: keyCode, modifiers: carbonModifiers)
            if success {
                let modifierString = modifiersString(modifiers)
                let keyString = keyString(for: keyCode)
                let finalString = "\(modifierString)\(keyString)"
                parent.currentShortcut = finalString
                UserDefaults.standard.set(finalString, forKey: UserDefaultsKey.captureShortcut)
                parent.isRecording = false
            } else {
                parent.isRecording = false
                parent.onConflict()
            }
        }
        
        func didCancel() {
            parent.isRecording = false
        }
        
        private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
            var result: UInt32 = 0
            if flags.contains(.command) { result |= UInt32(cmdKey) }
            if flags.contains(.option) { result |= UInt32(optionKey) }
            if flags.contains(.control) { result |= UInt32(controlKey) }
            if flags.contains(.shift) { result |= UInt32(shiftKey) }
            return result
        }
        
        private func modifiersString(_ modifiers: NSEvent.ModifierFlags) -> String {
            var result = ""
            if modifiers.contains(.control) { result += "Control + " }
            if modifiers.contains(.option) { result += "Option + " }
            if modifiers.contains(.shift) { result += "Shift + " }
            if modifiers.contains(.command) { result += "Command + " }
            return result
        }
        
        private func keyString(for keyCode: UInt16) -> String {
            // 简单的映射，实际应用中可以查表
            if keyCode == 0 { return "A" }
            if keyCode == 1 { return "S" }
            if keyCode == 2 { return "D" }
            if keyCode == 3 { return "F" }
            // ... fallback
            return "Key(\(keyCode))"
        }
    }
}

protocol RecorderNSViewDelegate: AnyObject {
    func didRecord(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
    func didCancel()
}

class RecorderNSView: NSView {
    weak var delegate: RecorderNSViewDelegate?
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // ESC
            delegate?.didCancel()
            return
        }
        
        // 必须要有修饰键
        if !flags.isEmpty {
            delegate?.didRecord(keyCode: event.keyCode, modifiers: flags)
        }
    }
}
