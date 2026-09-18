import Foundation

/// The indicator's title line: a renamed slot keeps its name, an automatically
/// named one shows the language's own name for itself.
public enum SlotTitleResolver {
    public static func title(slot: SwitchSlot, source: InputSourceInfo?) -> String {
        guard !isRenamed(slot, source: source),
              let language = source?.primaryLanguage,
              let endonym = endonym(forLanguageTag: language, code: language)
        else { return slot.name }
        return endonym
    }

    /// Titles for a whole slot list. Slots that would share a title fall back to the
    /// name of their full language tag when that tells them apart.
    public static func titles(
        for slots: [SwitchSlot],
        sources: [InputRole: InputSourceInfo]
    ) -> [InputRole: String] {
        let plain = slots.map { (slot: $0, title: title(slot: $0, source: sources[$0.id])) }
        let counts = Dictionary(plain.map { ($0.title, 1) }, uniquingKeysWith: +)
        return Dictionary(
            plain.map { entry -> (InputRole, String) in
                guard counts[entry.title, default: 0] > 1,
                      !isRenamed(entry.slot, source: sources[entry.slot.id]),
                      let tag = fullTag(of: sources[entry.slot.id]),
                      let specific = endonym(forLanguageTag: tag, code: nil),
                      specific != entry.title
                else { return (entry.slot.id, entry.title) }
                return (entry.slot.id, specific)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Layout direction follows the target language, not the language of the UI.
    public static func isRightToLeft(language: String?) -> Bool {
        guard let language, !language.isEmpty else { return false }
        return Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// "Renamed" is derived instead of stored: a name is automatic when it is one
    /// the app itself would have written for this slot.
    static func isRenamed(_ slot: SwitchSlot, source: InputSourceInfo?) -> Bool {
        let englishName = source?.primaryLanguage.flatMap {
            Locale(identifier: "en_US").localizedString(forLanguageCode: $0)
        }
        let automatic = [
            englishName,
            source?.localizedName,
            SwitchSlot.legacyDefaults.first { $0.id == slot.id }?.name,
            slot.id.rawValue,
        ]
        let name = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !automatic.contains { $0?.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Foundation reports some endonyms in lower case ("français"), so the first
    /// grapheme is capitalised with that language's own casing rules.
    private static func endonym(forLanguageTag tag: String, code: String?) -> String? {
        let locale = Locale(identifier: tag)
        let raw = if let code {
            locale.localizedString(forLanguageCode: code)
        } else {
            locale.localizedString(forIdentifier: tag)
        }
        guard let name = raw, let first = name.first else { return nil }
        return String(first).capitalized(with: locale) + name.dropFirst()
    }

    private static func fullTag(of source: InputSourceInfo?) -> String? {
        let tag = source?.languages.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return tag?.isEmpty == false ? tag : nil
    }
}
