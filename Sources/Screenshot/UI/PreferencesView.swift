import SwiftUI
import Carbon
import ServiceManagement

public struct PreferencesView: View {
    @State private var isRecording = false
    @State private var recordedShortcut: String = "Option + A"
    @State private var showConflictToast = false
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    
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
        VStack(alignment: .leading, spacing: 24) {
            Text(LanguageManager.shared.localizedString(forKey: "偏好设置"))
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(LanguageManager.shared.localizedString(forKey: "全局快捷键"))
                    .font(.headline)
                
                HStack {
                    Text(LanguageManager.shared.localizedString(forKey: "截图快捷键:"))
                    
                    Button(action: {
                        isRecording = true
                    }) {
                        Text(isRecording ? LanguageManager.shared.localizedString(forKey: "请按下新快捷键...") : recordedShortcut)
                            .frame(minWidth: 150)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(isRecording ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecording ? Color.blue : Color.gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
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
                
                if showConflictToast {
                    Text(LanguageManager.shared.localizedString(forKey: "快捷键冲突或无效，请尝试其他组合。"))
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                } else {
                    Text(LanguageManager.shared.localizedString(forKey: "点击上方按钮后直接按下组合键即可设置。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(LanguageManager.shared.localizedString(forKey: "注意：部分快捷键（如 Cmd+Space）被 macOS 系统全局保留，录制时若无反应请更换组合。"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text(LanguageManager.shared.localizedString(forKey: "常规设置"))
                    .font(.headline)
                
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
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text(LanguageManager.shared.localizedString(forKey: "多语言支持"))
                    .font(.headline)
                
                HStack {
                    Text(LanguageManager.shared.localizedString(forKey: "显示语言:"))
                    
                    Picker("", selection: $languageManager.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
                
                Text(LanguageManager.shared.localizedString(forKey: "TraceMark 默认跟随您的 macOS 系统语言。支持实时切换多种语言。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                UserDefaults.standard.set(finalString, forKey: "captureShortcut")
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
