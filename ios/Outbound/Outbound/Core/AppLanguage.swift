import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"

    static var current: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? AppLanguage.english.rawValue
        return language(matching: preferred)
    }

    static var currentIdentifier: String { current.rawValue }

    static var speechLocale: Locale {
        switch current {
        case .english: Locale(identifier: "en_US")
        case .spanish: Locale(identifier: "es_ES")
        case .simplifiedChinese: Locale(identifier: "zh_CN")
        }
    }

    static func language(matching identifier: String) -> AppLanguage {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh") { return .simplifiedChinese }
        if normalized.hasPrefix("es") { return .spanish }
        return .english
    }
}
