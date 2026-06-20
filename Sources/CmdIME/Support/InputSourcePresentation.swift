import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct InputSourcePresentation {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    init(source: InputSourceInfo?, fallbackRole: InputRole) {
        guard let source else {
            self = Self.fallback(for: fallbackRole)
            return
        }

        let sourceKind = InputSourceKind(source: source) ?? .unknown
        symbol = sourceKind.symbol
        title = sourceKind.title(source: source)
        detail = source.localizedName
        tint = sourceKind.tint
    }

    private static func fallback(for role: InputRole) -> InputSourcePresentation {
        let kind: InputSourceKind = switch role {
        case .english:
            .english
        case .chinese:
            .chinese
        case .japanese:
            .japanese
        }

        return InputSourcePresentation(
            symbol: kind.symbol,
            title: kind.title(source: nil),
            detail: "No input method selected",
            tint: kind.tint
        )
    }

    private init(symbol: String, title: String, detail: String, tint: Color) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tint = tint
    }
}

private enum InputSourceKind {
    case english
    case chinese
    case japanese
    case unknown

    init?(source: InputSourceInfo) {
        let languages = source.languages.map { $0.lowercased() }
        let text = ([source.id, source.localizedName] + languages).joined(separator: " ").lowercased()

        if languages.contains(where: { $0 == "ja" || $0.hasPrefix("ja-") })
            || text.contains("japanese")
            || text.contains("hiragana")
            || text.contains("kotoeri") {
            self = .japanese
        } else if languages.contains(where: { $0 == "zh" || $0.hasPrefix("zh-") })
            || text.contains("pinyin")
            || text.contains("chinese")
            || text.contains("simplified")
            || text.contains("scim")
            || text.contains("中文")
            || text.contains("拼音") {
            self = .chinese
        } else if languages.contains(where: { $0 == "en" || $0.hasPrefix("en-") })
            || text.contains("abc")
            || text.contains("u.s.")
            || text.contains("keylayout.us") {
            self = .english
        } else {
            self = .unknown
        }
    }

    var symbol: String {
        switch self {
        case .english:
            "A"
        case .chinese:
            "中"
        case .japanese:
            "あ"
        case .unknown:
            "⌘"
        }
    }

    func title(source: InputSourceInfo?) -> String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "中文"
        case .japanese:
            "日本語"
        case .unknown:
            source?.localizedName ?? "Input method"
        }
    }

    var tint: Color {
        switch self {
        case .english:
            CmdIMEDesign.Colors.role(.english)
        case .chinese:
            CmdIMEDesign.Colors.role(.chinese)
        case .japanese:
            CmdIMEDesign.Colors.role(.japanese)
        case .unknown:
            Color(nsColor: .secondaryLabelColor)
        }
    }
}
