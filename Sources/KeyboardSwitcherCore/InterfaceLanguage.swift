import Foundation

/// The language of the settings window (General > Language). The choice is kept the way macOS
/// keeps a per-app language (System Settings > General > Language & Region > Applications): an
/// `AppleLanguages` list in CmdIME's own defaults domain, read when the app launches. System
/// leaves the key out, so the window follows the macOS language.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system, english, simplifiedChinese, japanese

    /// The key in CmdIME's own defaults domain.
    public static let defaultsKey = "AppleLanguages"

    /// The list to store under `defaultsKey`; nil means remove the key.
    public var storedValue: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .simplifiedChinese: ["zh-Hans"]
        case .japanese: ["ja"]
        }
    }

    /// The language's name in that language, as macOS lists it; nil for System, whose name is
    /// localized by the app.
    public var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .japanese: "日本語"
        }
    }

    /// Reads a stored list by its first entry. A region suffix ("ja-JP") still names the language;
    /// a missing list, an empty one or any other language reads as System.
    public init(stored: [String]?) {
        guard let first = stored?.first else {
            self = .system
            return
        }
        self = Self.allCases.first { language in
            guard let code = language.storedValue?.first else { return false }
            return first == code || first.hasPrefix(code + "-")
        } ?? .system
    }
}
