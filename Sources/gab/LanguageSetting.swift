import Foundation

/// The spoken language Whisper is told to expect, persisted across launches.
/// Anything other than English needs a multilingual model (no `.en` suffix).
enum LanguageSetting {
    struct Language {
        let code: String   // Whisper language code, or "auto" to detect per dictation
        let label: String
    }

    static let auto = Language(code: "auto", label: "Auto-detect")

    static let languages: [Language] = [
        Language(code: "en", label: "English"),
        Language(code: "pt", label: "Português"),
        Language(code: "es", label: "Español"),
        Language(code: "fr", label: "Français"),
        Language(code: "de", label: "Deutsch"),
        Language(code: "it", label: "Italiano"),
    ]

    private static let selectionKey = "gab.selectedLanguage"

    /// Defaults to English, which works with every model.
    static var selectedCode: String {
        get { UserDefaults.standard.string(forKey: selectionKey) ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    static var needsMultilingualModel: Bool { selectedCode != "en" }

    static func label(for code: String) -> String {
        ([auto] + languages).first { $0.code == code }?.label ?? code
    }
}
