import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case zhHans
    case zhHant
    case en

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: return L10n.tr("lang.system")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        }
    }

    /// 真正用于查表的语言码。`.system` 会读取系统首选语言并归一化。
    var resolved: AppLanguage {
        switch self {
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            let lower = pref.lowercased()
            if lower.hasPrefix("zh") {
                if lower.contains("hant") || lower.contains("hk") || lower.contains("tw") || lower.contains("mo") {
                    return .zhHant
                }
                return .zhHans
            }
            return .en
        default:
            return self
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// UserDefaults key —— LocalizationManager 与 nonisolated 的 L10n 共用，避免魔法字符串漂移。
    static let preferredLanguageKey = "tc.preferredLanguage"

    @AppStorage(LocalizationManager.preferredLanguageKey) private var preferredLanguageRaw: String = AppLanguage.system.rawValue

    @Published var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.preferredLanguageKey) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .system
    }

    func update(_ lang: AppLanguage) {
        language = lang
        preferredLanguageRaw = lang.rawValue
    }

    func tr(_ key: String) -> String {
        L10n.lookup(key: key, language: language.resolved)
    }
}

enum L10n {
    /// Nonisolated 当前语言：直接读 UserDefaults，避免触碰 @MainActor 的
    /// LocalizationManager，使 tr(...) 可在任意隔离上下文调用。语言变更经
    /// `update(_:)` 写回同一 key，二者始终一致。
    static var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: LocalizationManager.preferredLanguageKey)
            ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    static func tr(_ key: String) -> String {
        lookup(key: key, language: currentLanguage.resolved)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let fmt = lookup(key: key, language: currentLanguage.resolved)
        return String(format: fmt, arguments: args)
    }

    static func lookup(key: String, language: AppLanguage) -> String {
        let table: [String: String]
        switch language {
        case .zhHans: table = Self.zhHans
        case .zhHant: table = Self.zhHant
        case .en:     table = Self.en
        case .system: table = Self.en
        }
        if let v = table[key] { return v }
        return Self.zhHans[key] ?? key
    }

    static let zhHans: [String: String] = LocalizationData.zhHans
    static let zhHant: [String: String] = LocalizationData.zhHant
    static let en: [String: String]     = LocalizationData.en
}

/// 让 View 在 LocalizationManager 改变时自动刷新的便捷扩展。
extension View {
    func localized() -> some View {
        modifier(LocalizedModifier())
    }
}

private struct LocalizedModifier: ViewModifier {
    @ObservedObject private var loc = LocalizationManager.shared
    func body(content: Content) -> some View {
        content.id(loc.language.rawValue)
    }
}
