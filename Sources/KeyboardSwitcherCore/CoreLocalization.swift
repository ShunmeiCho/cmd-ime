import Foundation

/// Core is shared with keyboardctl, including the copy embedded in CmdIME.app.
/// Only the GUI executable may consult the main bundle's Localizable table.
public enum CoreLocalization {
    public static func text(_ english: String, _ arguments: String...) -> String {
        resolve(english, arguments: arguments, bundle: .main,
                executablePath: CommandLine.arguments.first ?? "")
    }

    /// For presentation only. Never use localized names as persisted identifiers or defaults.
    public static func displayName(_ english: String) -> String { text(english) }

    static func resolve(_ english: String, arguments: [String] = [], bundle: Bundle,
                        executablePath: String) -> String {
        let isApp = URL(fileURLWithPath: executablePath).lastPathComponent == "CmdIME"
        let format = isApp ? bundle.localizedString(forKey: english, value: english, table: nil) : english
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), arguments: arguments)
    }
}
