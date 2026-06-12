import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    
    public var id: String { self.rawValue }
    
    public var displayName: LocalizedStringKey {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }
}

public class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    @AppStorage("AppLanguageSelection") public var selectedLanguage: AppLanguage = .system {
        didSet {
            updateLocale()
        }
    }
    
    @Published public var currentLocale: Locale
    
    private init() {
        // Initialize with saved preference
        let saved = UserDefaults.standard.string(forKey: "AppLanguageSelection") ?? AppLanguage.system.rawValue
        let lang = AppLanguage(rawValue: saved) ?? .system
        
        if lang == .system {
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.currentLocale = Locale(identifier: preferred)
        } else {
            self.currentLocale = Locale(identifier: lang.rawValue)
        }
        self.selectedLanguage = lang
    }
    
    private func updateLocale() {
        if selectedLanguage == .system {
            let preferred = Locale.preferredLanguages.first ?? "en"
            currentLocale = Locale(identifier: preferred)
        } else {
            currentLocale = Locale(identifier: selectedLanguage.rawValue)
        }
        NotificationCenter.default.post(name: NSNotification.Name("LanguageDidChange"), object: nil)
    }
    
    public func localizedString(forKey key: String) -> String {
        let code: String
        if selectedLanguage == .system {
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.starts(with: "zh-Hant") {
                code = "zh-Hant"
            } else if preferred.starts(with: "zh") {
                code = "zh-Hans"
            } else if preferred.starts(with: "ja") {
                code = "ja"
            } else if preferred.starts(with: "ko") {
                code = "ko"
            } else {
                code = "en"
            }
        } else {
            code = selectedLanguage.rawValue
        }
        
        // Find the bundle for the specific language
        var bundlePath = Bundle.main.path(forResource: code, ofType: "lproj")
        
        // Handle variations
        if bundlePath == nil {
             bundlePath = Bundle.main.path(forResource: code.lowercased(), ofType: "lproj")
        }
        
        if bundlePath == nil, let langCode = code.components(separatedBy: "-").first {
             bundlePath = Bundle.main.path(forResource: langCode, ofType: "lproj")
             if bundlePath == nil {
                 bundlePath = Bundle.main.path(forResource: langCode.lowercased(), ofType: "lproj")
             }
        }
        
        // Fallback to English
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: "en", ofType: "lproj")
        }
        
        guard let path = bundlePath, let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

public struct LanguageInjectViewModifier: ViewModifier {
    @ObservedObject var languageManager = LanguageManager.shared
    
    public func body(content: Content) -> some View {
        content
            .environment(\.locale, languageManager.currentLocale)
    }
}

extension View {
    public func applyAppLanguage() -> some View {
        self.modifier(LanguageInjectViewModifier())
    }
}
