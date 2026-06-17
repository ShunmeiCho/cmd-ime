import Foundation

public enum InputSourceMatcher {
    public static func bestMatch(
        for role: InputRole,
        sources: [InputSourceInfo],
        config: SwitcherConfig
    ) -> InputSourceInfo? {
        let selectable = selectableSources(from: sources)
        let preference = config.preference(for: role)

        for id in preference.preferredIDs {
            if let source = selectable.first(where: { $0.id == id }) {
                return source
            }
        }

        let languagePrefixes = preference.languagePrefixes.map { $0.lowercased() }
        if let source = selectable.first(where: { source in
            source.languages.contains { language in
                let normalized = language
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "-")
                return languagePrefixes.contains { normalized.hasPrefix($0) }
            }
        }) {
            return source
        }

        let nameFragments = preference.nameContains.map { $0.lowercased() }
        return selectable.first { source in
            let name = source.localizedName.lowercased()
            return nameFragments.contains { name.contains($0) }
        }
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
