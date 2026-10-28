import Foundation

enum Language: String, CaseIterable, Identifiable {
    case zh, en

    static let storageKey = "language"

    /// Chinese if the system prefers it, otherwise English.
    static var systemDefault: Language {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }

    /// The language currently chosen in the app (for code without access to the view's setting).
    static var current: Language {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Language.init(rawValue:)) ?? systemDefault
    }

    var id: Self { self }

    /// Native name, so each option is recognizable whichever language is active.
    var name: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// Picks the string for this language.
    func pick(_ zh: String, _ en: String) -> String {
        self == .zh ? zh : en
    }
}
