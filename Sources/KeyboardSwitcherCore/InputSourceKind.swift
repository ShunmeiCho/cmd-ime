/// Presentation category, determined only by the primary language when available.
public enum InputSourceKind: Equatable, Sendable {
    case english
    case chinese
    case japanese
    case unknown

    public init(source: InputSourceInfo) {
        if let language = source.primaryLanguage {
            self = switch language {
            case "en": .english
            case "zh": .chinese
            case "ja": .japanese
            default: .unknown
            }
            return
        }

        // Legacy sources without language metadata retain their ID/name heuristics.
        let text = [source.id, source.localizedName].joined(separator: " ").lowercased()
        if text.contains("japanese")
            || text.contains("hiragana")
            || text.contains("kotoeri") {
            self = .japanese
        } else if text.contains("pinyin")
            || text.contains("chinese")
            || text.contains("simplified")
            || text.contains("scim")
            || text.contains("中文")
            || text.contains("拼音") {
            self = .chinese
        } else if text.contains("abc")
            || text.contains("u.s.")
            || text.contains("keylayout.us") {
            self = .english
        } else {
            self = .unknown
        }
    }

    public func symbol(source: InputSourceInfo) -> String {
        switch self {
        case .english: "A"
        case .chinese: "中"
        case .japanese: "あ"
        case .unknown: source.badgeSymbol
        }
    }

    public func title(fallback: String) -> String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        case .japanese: "日本語"
        case .unknown: fallback
        }
    }
}
