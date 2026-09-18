import Foundation

/// Shared menu/execution policy. Ownership means the first declared preferred ID,
/// not a fallback match or an entry in a legacy slot's history.
public enum SlotSourceSelection: Equatable, Sendable {
    case unchanged
    case assign
    case swap(with: InputRole)
    case usedBy(InputRole)
    case unavailable

    public var isEnabled: Bool {
        switch self {
        case .unchanged, .assign, .swap: true
        case .usedBy, .unavailable: false
        }
    }
}

extension SwitcherConfig {
    public func inputSourceSelection(_ source: InputSourceInfo, for role: InputRole,
                                     sources: [InputSourceInfo]) -> SlotSourceSelection {
        guard slot(role) != nil, !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              InputSourceMatcher.selectableSources(from: sources).contains(where: { $0.id == source.id }) else {
            return .unavailable
        }
        let owners = slots.filter { $0.id != role && preference(for: $0.id).preferredIDs.first == source.id }
        if let owner = owners.first {
            guard owners.count == 1,
                  (try? swappingInputSources(between: role, and: owner.id, sources: sources)) != nil else {
                return .usedBy(owner.id)
            }
            return .swap(with: owner.id)
        }
        if preference(for: role).preferredIDs.first == source.id { return .unchanged }
        return .assign
    }

    public func selectingInputSource(_ source: InputSourceInfo, for role: InputRole,
                                     sources: [InputSourceInfo]) throws(SlotError) -> SwitcherConfig {
        guard slot(role) != nil else { throw .unknownSlot(role) }
        switch inputSourceSelection(source, for: role, sources: sources) {
        case .unchanged: return self
        case .assign: return try assigningInputSource(source, to: role)
        case let .swap(other): return try swappingInputSources(between: role, and: other, sources: sources)
        case .usedBy: throw .sourceAlreadyUsed
        case .unavailable: throw .invalidSource
        }
    }

    /// Atomically exchanges declared first preferences, leaving identity, triggers,
    /// and legacy matching rules/history attached to their original slots.
    /// When a preferred source is missing but a fallback resolves, transfer the
    /// missing ID (and its saved language), not the temporary resolved ID. This
    /// lets the recipient restore the preferred source when it is reinstalled.
    /// With no declared preference, the resolved source supplies the initial pin.
    public func swappingInputSources(between first: InputRole, and second: InputRole,
                                    sources: [InputSourceInfo]) throws(SlotError) -> SwitcherConfig {
        guard slot(first) != nil else { throw .unknownSlot(first) }
        guard slot(second) != nil else { throw .unknownSlot(second) }
        guard first != second else { return self }
        guard let firstMatch = InputSourceMatcher.bestMatch(for: first, sources: sources, config: self),
              let secondMatch = InputSourceMatcher.bestMatch(for: second, sources: sources, config: self) else {
            throw .invalidSource
        }
        let firstPreference = preference(for: first)
        let secondPreference = preference(for: second)
        let firstID = firstPreference.preferredIDs.first ?? firstMatch.id
        let secondID = secondPreference.preferredIDs.first ?? secondMatch.id
        guard !firstID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secondID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .invalidSource }
        guard firstID != secondID,
              !slots.contains(where: {
                  $0.id != first && $0.id != second
                      && [firstID, secondID].contains(preference(for: $0.id).preferredIDs.first ?? "")
              }) else { throw .sourceAlreadyUsed }

        func language(for id: String, preference: RoleInputSourcePreference, match: InputSourceInfo) -> String? {
            if let installed = InputSourceMatcher.selectableSources(from: sources).first(where: { $0.id == id }) {
                return installed.primaryLanguage
            }
            return preference.fallbackLanguage ?? match.primaryLanguage
        }
        var result = self
        result.setSwappedPreference(secondID, language: language(for: secondID, preference: secondPreference, match: secondMatch), for: first)
        result.setSwappedPreference(firstID, language: language(for: firstID, preference: firstPreference, match: firstMatch), for: second)
        return result
    }

    private mutating func setSwappedPreference(_ id: String, language: String?, for role: InputRole) {
        var preference = preference(for: role)
        // Same pin semantics as assigningInputSource; never exchange whole preferences.
        if preference.fallbackLanguage == nil && (InputRole.legacy.contains(role) || !preference.languagePrefixes.isEmpty || !preference.nameContains.isEmpty) {
            pinInputSourceID(id, for: role)
        } else {
            preference.preferredIDs = [id]
            preference.fallbackLanguage = language
            inputSources[role.rawValue] = preference
        }
    }
}
