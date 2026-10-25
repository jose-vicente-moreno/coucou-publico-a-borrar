#if !APPSTORE
import Foundation

// MARK: - VoiceLang
//
// The languages Coucou listens to and answers in. The raw values are the codes stored in
// UserDefaults ("voiceLanguage", "voiceListenLanguage"): never rename them.
// Pure Foundation: compiled by the voice test scripts.
enum VoiceLang: String, CaseIterable, Sendable {
    case fr, en, es

    /// "fr", "fr-FR", "es_MX"… → that language; anything else → English, the default.
    init(code: String?) {
        self = Self.supported(code) ?? .en
    }

    /// The language of a locale (nil → English).
    init(locale: Locale?) {
        self.init(code: locale?.language.languageCode?.identifier)
    }

    /// Only the languages Coucou speaks: nil for "de", "it", "auto"…
    static func supported(_ code: String?) -> VoiceLang? {
        guard let code else { return nil }
        let base = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return VoiceLang(rawValue: base)
    }

    /// Speech recognition and answers.
    var localeId: String {
        switch self {
        case .fr: return "fr-FR"
        case .en: return "en-US"
        case .es: return "es-ES"
        }
    }
    var locale: Locale { Locale(identifier: localeId) }

    /// Money, dates and durations ("fr_FR", "en_US", "es_ES").
    var formatLocale: Locale { Locale(identifier: localeId.replacingOccurrences(of: "-", with: "_")) }

    /// Shown in Settings: "Français", "English", "Español".
    var nativeName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// For the prompts of the voice brains: "French", "English", "Spanish".
    var englishName: String { name(in: .en) }

    /// This language's name, said in `lang`: .en.name(in: .fr) = "anglais".
    func name(in lang: VoiceLang) -> String {
        switch (self, lang) {
        case (.fr, .fr): return "français"
        case (.en, .fr): return "anglais"
        case (.es, .fr): return "espagnol"
        case (.fr, .en): return "French"
        case (.en, .en): return "English"
        case (.es, .en): return "Spanish"
        case (.fr, .es): return "francés"
        case (.en, .es): return "inglés"
        case (.es, .es): return "español"
        }
    }

    /// The sentence in this language.
    func t(_ fr: String, _ en: String, _ es: String) -> String {
        switch self {
        case .fr: return fr
        case .en: return en
        case .es: return es
        }
    }
}
#endif
