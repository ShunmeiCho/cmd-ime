import Foundation

public enum InputSourceMatcher {
    public static func bestMatch(
        for role: InputRole,
        sources: [InputSourceInfo],
        config: SwitcherConfig
    ) -> InputSourceInfo? {
        let selectable = sources.filter(\.isSelectCapable)
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
}

