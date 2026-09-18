import Foundation

/// Which tier of `InputSourceMatcher.bestMatch` produced a match, and the
/// specific configured value that matched.
public enum InputSourceMatchTier: String, Equatable, Sendable {
    case preferredID
    case languagePrefix
    case nameContains
    case none
}

/// The outcome of matching a role's preference against a set of input
/// sources: the source that matched (if any), which tier matched, and the
/// specific configured value responsible for the match.
public struct InputSourceMatchResult: Equatable, Sendable {
    public var source: InputSourceInfo?
    public var tier: InputSourceMatchTier
    public var matchedValue: String?

    public init(source: InputSourceInfo?, tier: InputSourceMatchTier, matchedValue: String?) {
        self.source = source
        self.tier = tier
        self.matchedValue = matchedValue
    }
}

public enum InputSourceMatcher {
    public static func bestMatch(
        for role: InputRole,
        sources: [InputSourceInfo],
        config: SwitcherConfig
    ) -> InputSourceInfo? {
        match(for: role, sources: sources, config: config).source
    }

    /// Same matching logic as `bestMatch`, but also reports which tier
    /// matched and which configured value was responsible, so callers (e.g.
    /// `keyboardctl diagnose`) can never diverge from the actual selection
    /// behavior.
    public static func match(
        for role: InputRole,
        sources: [InputSourceInfo],
        config: SwitcherConfig
    ) -> InputSourceMatchResult {
        let selectable = selectableSources(from: sources)
        let preference = config.preference(for: role)

        for id in preference.preferredIDs {
            if let source = selectable.first(where: { $0.id == id }) {
                return InputSourceMatchResult(source: source, tier: .preferredID, matchedValue: id)
            }
        }

        // Iterate sources first (not prefixes first) to match `bestMatch`'s
        // original tie-breaking: the first selectable source that matches
        // any prefix wins, regardless of prefix order.
        let languagePrefixes = preference.languagePrefixes.map { $0.lowercased() }
        for source in selectable {
            let matchedPrefix = source.languages.lazy.compactMap { language -> String? in
                let normalized = language
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "-")
                return languagePrefixes.first { normalized.hasPrefix($0) }
            }.first
            if let matchedPrefix {
                return InputSourceMatchResult(source: source, tier: .languagePrefix, matchedValue: matchedPrefix)
            }
        }

        let nameFragments = preference.nameContains.map { $0.lowercased() }
        for source in selectable {
            let name = source.localizedName.lowercased()
            if let matchedFragment = nameFragments.first(where: { name.contains($0) }) {
                return InputSourceMatchResult(source: source, tier: .nameContains, matchedValue: matchedFragment)
            }
        }

        return InputSourceMatchResult(source: nil, tier: .none, matchedValue: nil)
    }

    public static func selectableSources(from sources: [InputSourceInfo]) -> [InputSourceInfo] {
        sources.filter { $0.isSelectCapable && !isAuxiliaryInputSource($0) }
    }

    public static func isAuxiliaryInputSource(_ source: InputSourceInfo) -> Bool {
        let id = source.id.lowercased()
        let name = source.localizedName.lowercased()
        return id.contains("palette")
            || id.contains("pressandhold")
            || id.contains("dictation")
            || name.contains("palette")
            || name.contains("emoji")
            || name.contains("symbols")
            || name.contains("dictation")
    }
}
