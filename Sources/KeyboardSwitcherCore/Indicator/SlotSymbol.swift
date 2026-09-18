import Foundation

/// What the indicator tile shows for a slot: a glyph, plus a small mark when two
/// slots would otherwise share the glyph.
public struct SlotSymbol: Equatable, Sendable {
    public let glyph: String
    public let mark: String?

    public init(glyph: String, mark: String? = nil) {
        self.glyph = glyph
        self.mark = mark
    }
}

/// Resolves pairwise-distinct symbols for a whole slot list, so colour is never
/// the only thing that tells two slots apart.
public enum SlotSymbolResolver {
    static let maxOverrideGraphemes = 2
    static let latinGlyph = "A"
    static let unknownGlyph = "?"
    static let simplifiedGlyph = "简"
    static let traditionalGlyph = "繁"

    /// Per language, so that languages sharing a script stay distinct.
    static let languageGlyphs: [String: String] = [
        "zh": "中", "yue": "粵", "ja": "あ", "ko": "한",
        "ru": "Я", "uk": "Ї", "be": "Ў", "bg": "Ъ", "sr": "Ђ", "mk": "Ѓ", "kk": "Қ", "mn": "Ө",
        "ar": "ع", "fa": "پ", "ur": "ے", "ps": "ښ", "ckb": "ڕ", "he": "א", "yi": "ײ", "el": "Ω",
        "hi": "अ", "mr": "म", "ne": "न", "bn": "অ", "pa": "ਅ", "gu": "અ", "ta": "அ", "te": "అ",
        "kn": "ಅ", "ml": "അ", "si": "අ", "th": "ก", "lo": "ກ", "km": "ក", "my": "က", "bo": "ཀ",
        "ka": "ქ", "hy": "Ա", "am": "አ",
    ]

    /// For a non-Latin language missing from the language table.
    static let scriptGlyphs: [String: String] = [
        "Cyrl": "Ж", "Arab": "ع", "Hebr": "א", "Grek": "Ω", "Deva": "अ",
        "Hans": "中", "Hant": "中", "Hani": "中", "Kore": "한", "Jpan": "あ",
    ]

    public static func symbols(
        for slots: [SwitchSlot],
        sources: [InputRole: InputSourceInfo]
    ) -> [InputRole: SlotSymbol] {
        let overrides = Dictionary(
            slots.compactMap { slot in validatedOverride(slot.symbol).map { (slot.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let automatic = slots.filter { overrides[$0.id] == nil }
        let latinCount = automatic.filter { isLatin(language(of: sources[$0.id])) }.count

        let glyphs = automatic.map { slot -> (slot: SwitchSlot, glyph: String) in
            let source = sources[slot.id]
            let tag = language(of: source)
            if latinCount > 1, isLatin(tag), let code = source?.primaryLanguage {
                return (slot, String(code.prefix(2)).uppercased())
            }
            return (slot, tableGlyph(language: tag) ?? firstGrapheme(of: source?.localizedName)
                ?? firstGrapheme(of: slot.name) ?? unknownGlyph)
        }
        let separated = separatingChineseScripts(glyphs, sources: sources)

        var result = overrides.mapValues { SlotSymbol(glyph: $0) }
        for (glyph, group) in Dictionary(grouping: separated, by: \.glyph) {
            let marks = group.count > 1 ? tieMarks(for: group.map(\.slot), sources: sources) : []
            for (offset, member) in group.enumerated() {
                result[member.slot.id] = SlotSymbol(glyph: glyph, mark: marks.isEmpty ? nil : marks[offset])
            }
        }
        return result
    }

    /// The glyph for one source on its own, before any tie-break with other slots.
    public static func baseGlyph(language: String?, sourceName: String) -> String {
        tableGlyph(language: normalized(language)) ?? firstGrapheme(of: sourceName) ?? unknownGlyph
    }

    /// Trimmed override when it is one or two visible grapheme clusters, else nil.
    public static func validatedOverride(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...maxOverrideGraphemes).contains(trimmed.count),
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              })
        else { return nil }
        return trimmed
    }

    // MARK: - Rule steps

    private static func tableGlyph(language tag: String?) -> String? {
        guard let tag else { return nil }
        let primary = tag.components(separatedBy: "-")[0]
        if let glyph = languageGlyphs[primary] { return glyph }
        guard let script = script(of: tag) else { return nil }
        return script == "Latn" ? latinGlyph : scriptGlyphs[script]
    }

    /// zh-Hans and zh-Hant share a glyph; when both are present each names its script.
    private static func separatingChineseScripts(
        _ glyphs: [(slot: SwitchSlot, glyph: String)],
        sources: [InputRole: InputSourceInfo]
    ) -> [(slot: SwitchSlot, glyph: String)] {
        let chinese = languageGlyphs["zh"]
        let scripts = glyphs.filter { $0.glyph == chinese }
            .compactMap { language(of: sources[$0.slot.id]).flatMap(script) }
        guard Set(scripts).count > 1 else { return glyphs }
        return glyphs.map { entry in
            guard entry.glyph == chinese else { return entry }
            switch language(of: sources[entry.slot.id]).flatMap(script) {
            case "Hans": return (entry.slot, simplifiedGlyph)
            case "Hant": return (entry.slot, traditionalGlyph)
            default: return entry
            }
        }
    }

    /// First grapheme of each source name; ordinals in slot order when those collide.
    private static func tieMarks(for group: [SwitchSlot], sources: [InputRole: InputSourceInfo]) -> [String] {
        let initials = group.map { firstGrapheme(of: sources[$0.id]?.localizedName) }
        let distinct = Set(initials.compactMap { $0 })
        guard distinct.count == group.count else { return group.indices.map { String($0 + 1) } }
        return initials.compactMap { $0 }
    }

    // MARK: - Language helpers

    private static func language(of source: InputSourceInfo?) -> String? {
        normalized(source?.languages.first)
    }

    private static func normalized(_ language: String?) -> String? {
        guard let language else { return nil }
        let tag = language.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        guard let primary = tag.components(separatedBy: "-").first, !primary.isEmpty else { return nil }
        return ([primary.lowercased()] + tag.components(separatedBy: "-").dropFirst()).joined(separator: "-")
    }

    private static func script(of tag: String) -> String? {
        Locale.Language(identifier: tag).script?.identifier
    }

    private static func isLatin(_ tag: String?) -> Bool {
        guard let tag, languageGlyphs[tag.components(separatedBy: "-")[0]] == nil else { return false }
        return script(of: tag) == "Latn"
    }

    private static func firstGrapheme(of text: String?) -> String? {
        guard let first = text?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }
}

public extension SwitcherConfig {
    /// Sets or clears (nil or blank) the slot's symbol override.
    func settingSlotSymbol(_ symbol: String?, for id: InputRole) throws(SlotError) -> SwitcherConfig {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { throw .unknownSlot(id) }
        let isBlank = symbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let validated = SlotSymbolResolver.validatedOverride(symbol)
        guard isBlank || validated != nil else { throw .invalidSymbol(symbol ?? "") }
        var result = self
        result.slots[index].symbol = validated
        return result
    }
}
