/// Explains the actual matcher result relative to the slot's first preferred ID.
public enum SlotMatchExplanation: Equatable, Sendable {
    case pinned
    case unavailablePreferred(preferredID: String, using: InputSourceInfo)
    case automatic(source: InputSourceInfo)
    case unmatched

    public static func resolve(
        for role: InputRole,
        sources: [InputSourceInfo],
        config: SwitcherConfig
    ) -> Self {
        let match = InputSourceMatcher.match(for: role, sources: sources, config: config)
        guard let source = match.source else { return .unmatched }

        if let preferredID = config.preference(for: role).preferredIDs.first {
            if match.tier == .preferredID && source.id == preferredID {
                return .pinned
            }
            // Secondary preferred IDs are alternatives, not the designated pin.
            if source.id != preferredID {
                return .unavailablePreferred(preferredID: preferredID, using: source)
            }
        }
        return .automatic(source: source)
    }
}
