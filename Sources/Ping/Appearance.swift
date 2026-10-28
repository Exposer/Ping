import AppKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    func title(in language: Language) -> String {
        switch self {
        case .system: return language.pick("跟随系统", "System")
        case .light: return language.pick("浅色", "Light")
        case .dark: return language.pick("深色", "Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// Set on NSApp rather than via `.preferredColorScheme`, which on macOS
    /// doesn't reliably switch back once set to nil.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
