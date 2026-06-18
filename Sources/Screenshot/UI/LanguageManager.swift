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
    
    /// 定位 SwiftPM 资源 bundle，避免自动生成的 Bundle.module 在 .app 包中找不到时 fatalError。
    /// 查找顺序：Contents/Resources -> .app 根目录 -> 构建目录 -> Bundle.main
    private var resolvedResourceBundle: Bundle {
        let bundleName = "TraceMark_TraceMark"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle"),
            Bundle(for: LanguageManager.self).resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".build/x86_64-apple-macosx/release/\(bundleName).bundle"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".build/arm64-apple-macosx/release/\(bundleName).bundle"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".build/debug/\(bundleName).bundle")
        ]
        for candidate in candidates {
            if let url = candidate, let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.main
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

        // 直接解析 .lproj/Localizable.strings，绕过 Bundle 查找的兼容性问题
        let candidates = [resolvedResourceBundle, Bundle.main]
        let lprojNames = [code, code.lowercased(), code.components(separatedBy: "-").first, code.components(separatedBy: "-").first?.lowercased()].compactMap { $0 }

        for bundle in candidates {
            for lprojName in lprojNames {
                // 方案 A：直接读取 .strings 文件作为 plist
                if let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(lprojName).lproj"),
                   let dict = try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String],
                   let value = dict[key], !value.isEmpty {
                    return value
                }
                
                // 方案 B：尝试读取 .strings 为文本并解析（兼容 SPM 可能未编译为 binary plist 的情况）
                if let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(lprojName).lproj"),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    // 简单正则匹配 "key" = "value";
                    let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*=\\s*\"([^\"]+)\"\\s*;"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)),
                       match.numberOfRanges > 1,
                       let valueRange = Range(match.range(at: 1), in: content) {
                        return String(content[valueRange])
                    }
                }
            }
        }
        
        // 最终回退：使用系统默认 NSLocalizedString
        let result = NSLocalizedString(key, comment: "")
        return result.isEmpty ? key : result
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
