import Foundation

/// Toggle (CONTEXT.md): one trigger that switches between two slots. It is an ordinary binding whose
/// action is `toggleSlots`; at most one exists.
public enum ToggleBindingError: Error, Equatable, LocalizedError, Sendable {
    case reservedByMacOS(KeyTrigger)
    case conflictingBinding(KeyBinding)
    case sameSlot
    case unknownSlot(InputRole)

    public var errorDescription: String? {
        switch self {
        case let .reservedByMacOS(trigger): CoreLocalization.text("%@ is reserved by macOS input source switching", String(describing: trigger.displayName))
        case let .conflictingBinding(binding): CoreLocalization.text("The trigger %@ is already assigned.", String(describing: binding.trigger.displayName))
        case .sameSlot: CoreLocalization.text("Toggle needs two different slots.")
        case let .unknownSlot(id): CoreLocalization.text("Unknown slot \"%@\".", String(describing: id.rawValue))
        }
    }
}

extension SwitcherConfig {
    public static let toggleDisplayName = CoreLocalization.text("Toggle")

    public var toggleBinding: KeyBinding? {
        bindings.first { $0.enabled && $0.action.type == .toggleSlots }
    }

    /// The two slots the Toggle switches between, when it names two slots that exist.
    public var toggleSlots: (InputRole, InputRole)? {
        guard let roles = toggleBinding?.action.roles, roles.count == 2,
              roles[0] != roles[1], slot(roles[0]) != nil, slot(roles[1]) != nil else { return nil }
        return (roles[0], roles[1])
    }

    /// The binding a Toggle on `trigger` takes over: a trigger of one of its own two slots, which the
    /// Toggle reaches anyway. Nil when the trigger is free or another binding owns it.
    public func toggleTakeover(of trigger: KeyTrigger, slots first: InputRole, _ second: InputRole) -> KeyBinding? {
        bindings.first {
            $0.enabled && $0.action.type == .switchInputSource && ($0.action.role == first || $0.action.role == second)
                && Self.triggers($0.trigger, collideWith: trigger)
        }
    }

    /// Replaces the Toggle, or removes it when `trigger` is nil. A trigger one of its two slots has is
    /// taken from that slot (the Toggle reaches it anyway); a trigger anything else answers to is
    /// refused, with the rule Peek uses. A trigger the old Toggle took goes back to its slot once the
    /// Toggle no longer uses it, when that slot still exists and nothing else has taken the key.
    public func replacingToggleBinding(with trigger: KeyTrigger?, slots first: InputRole, _ second: InputRole) throws(ToggleBindingError) -> SwitcherConfig {
        var result = self
        let previous = toggleBinding
        result.bindings.removeAll { $0.action.type == .toggleSlots }
        guard let trigger else { return result.givingBack(previous) }
        try validateToggle(first, second)
        if trigger.isReservedMacInputSourceShortcut {
            throw .reservedByMacOS(trigger)
        }
        // The same key as before keeps the slot it came from; a key taken now records its slot.
        var takenFrom = previous?.trigger == trigger ? previous?.action.takenFrom : nil
        while let taken = result.toggleTakeover(of: trigger, slots: first, second) {
            takenFrom = takenFrom ?? taken.action.role
            result.bindings.removeAll { $0 == taken }
        }
        if let occupant = result.bindings.first(where: { $0.enabled && Self.triggers($0.trigger, collideWith: trigger) }) {
            throw .conflictingBinding(occupant)
        }
        if previous?.trigger != trigger {
            result = result.givingBack(previous)
        }
        result.bindings.append(KeyBinding(trigger: trigger, action: .toggleSlots(first, second, takenFrom: takenFrom)))
        return result
    }

    /// The slot and trigger a Toggle would hand back if it let go of its key now, for the status line.
    public func toggleGiveBack(of binding: KeyBinding?) -> (slot: InputRole, trigger: KeyTrigger)? {
        guard let binding, let slot = binding.action.takenFrom, self.slot(slot) != nil,
              !bindings.contains(where: { $0.enabled && $0 != binding && Self.triggers($0.trigger, collideWith: binding.trigger) }) else {
            return nil
        }
        return (slot, binding.trigger)
    }

    func givingBack(_ previous: KeyBinding?) -> SwitcherConfig {
        guard let (slot, trigger) = toggleGiveBack(of: previous) else { return self }
        var result = self
        result.bindings.append(KeyBinding(trigger: trigger, action: .switchInputSource(slot)))
        return result
    }

    /// The CLI's `bind <trigger> toggle <a> <b>`: like `bind` for a slot, it takes the trigger from
    /// whatever had it. Returns the bindings it displaced so the caller can say so.
    public mutating func upsertToggleBinding(trigger: KeyTrigger, slots first: InputRole, _ second: InputRole) throws(ToggleBindingError) -> [KeyBinding] {
        try validateToggle(first, second)
        let previous = toggleBinding
        let displaced = bindings.filter { $0.trigger == trigger && $0.action.type != .toggleSlots }
        // As in Settings: a key one of the two slots had is remembered, and a key the old Toggle took goes back.
        let takenFrom = displaced.first { $0.action.type == .switchInputSource && ($0.action.role == first || $0.action.role == second) }?
            .action.role ?? (previous?.trigger == trigger ? previous?.action.takenFrom : nil)
        bindings.removeAll { $0.trigger == trigger || $0.action.type == .toggleSlots }
        if previous?.trigger != trigger {
            self = givingBack(previous)
        }
        bindings.append(KeyBinding(trigger: trigger, action: .toggleSlots(first, second, takenFrom: takenFrom)))
        return displaced
    }

    private func validateToggle(_ first: InputRole, _ second: InputRole) throws(ToggleBindingError) {
        guard first != second else { throw .sameSlot }
        for id in [first, second] where slot(id) == nil {
            throw .unknownSlot(id)
        }
    }
}

/// Which slot a Toggle switches to.
public enum ToggleDecision {
    /// From one of the two slots, the other; from anywhere else (or when the slot in front is not
    /// known), the one of the two switched to last, the first when neither has been yet.
    /// `recentSlots` lists slots most recent first.
    public static func target(first: InputRole, second: InputRole, current: InputRole?, recentSlots: [InputRole]) -> InputRole {
        if current == first { return second }
        if current == second { return first }
        return recentSlots.first { $0 == first || $0 == second } ?? first
    }
}
