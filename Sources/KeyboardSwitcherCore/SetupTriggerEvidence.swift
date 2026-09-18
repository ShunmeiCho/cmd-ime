/// Emitted only after an event-tap trigger successfully selects its input source.
public struct SetupTriggeredSwitch: Equatable, Sendable {
    public let slotID: InputRole
    public let sourceID: String
    public let trigger: KeyTrigger

    public init(slotID: InputRole, sourceID: String, trigger: KeyTrigger) {
        self.slotID = slotID
        self.sourceID = sourceID
        self.trigger = trigger
    }
}

/// Only configuration that affects what a slot's triggers select belongs in this fingerprint.
public struct SetupTriggerFingerprint: Equatable, Sendable {
    public let triggers: Set<KeyTrigger>
    public let preference: RoleInputSourcePreference
    public let sourceID: String

    public init?(slotID: InputRole, config: SwitcherConfig, sources: [InputSourceInfo]) {
        guard config.slot(slotID) != nil,
              let source = InputSourceMatcher.bestMatch(for: slotID, sources: sources, config: config) else { return nil }
        let triggers = Set(config.slotTriggers.filter { $0.slot == slotID }.map(\.trigger))
        guard !triggers.isEmpty else { return nil }
        self.triggers = triggers
        preference = config.preference(for: slotID)
        sourceID = source.id
    }
}

/// Session-only evidence. Reconcile every configuration/source update, including deletion,
/// so restoring an identical ID later cannot resurrect proof from its previous lifetime.
public struct SetupTriggerEvidence: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let event: SetupTriggeredSwitch
        let fingerprint: SetupTriggerFingerprint
    }
    private var entries: [InputRole: Entry] = [:]

    public init() {}

    public func recording(_ event: SetupTriggeredSwitch, config: SwitcherConfig, sources: [InputSourceInfo]) -> Self {
        var result = reconciling(config: config, sources: sources)
        guard let fingerprint = SetupTriggerFingerprint(slotID: event.slotID, config: config, sources: sources),
              fingerprint.triggers.contains(event.trigger), fingerprint.sourceID == event.sourceID else { return result }
        result.entries[event.slotID] = Entry(event: event, fingerprint: fingerprint)
        return result
    }

    public func reconciling(config: SwitcherConfig, sources: [InputSourceInfo]) -> Self {
        var result = self
        result.entries = entries.filter { id, entry in
            SetupTriggerFingerprint(slotID: id, config: config, sources: sources) == entry.fingerprint
        }
        return result
    }

    public func triedSlotIDs(config: SwitcherConfig, sources: [InputSourceInfo]) -> Set<InputRole> {
        Set(reconciling(config: config, sources: sources).entries.keys)
    }
}
