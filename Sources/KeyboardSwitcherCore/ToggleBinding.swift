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
    /// refused, with the rule Peek uses.
    public func replacingToggleBinding(with trigger: KeyTrigger?, slots first: InputRole, _ second: InputRole) throws(ToggleBindingError) -> SwitcherConfig {
        var result = self
        result.bindings.removeAll { $0.action.type == .toggleSlots }
        guard let trigger else { return result }
        try validateToggle(first, second)
        if trigger.isReservedMacInputSourceShortcut {
            throw .reservedByMacOS(trigger)
        }
        while let taken = result.toggleTakeover(of: trigger, slots: first, second) {
            result.bindings.removeAll { $0 == taken }
        }
        if let occupant = result.bindings.first(where: { $0.enabled && Self.triggers($0.trigger, collideWith: trigger) }) {
            throw .conflictingBinding(occupant)
        }
        result.bindings.append(KeyBinding(trigger: trigger, action: .toggleSlots(first, second)))
        return result
    }

    /// The CLI's `bind <trigger> toggle <a> <b>`: like `bind` for a slot, it takes the trigger from
    /// whatever had it. Returns the bindings it displaced so the caller can say so.
    public mutating func upsertToggleBinding(trigger: KeyTrigger, slots first: InputRole, _ second: InputRole) throws(ToggleBindingError) -> [KeyBinding] {
        try validateToggle(first, second)
        let displaced = bindings.filter { $0.trigger == trigger && $0.action.type != .toggleSlots }
        bindings.removeAll { $0.trigger == trigger || $0.action.type == .toggleSlots }
        bindings.append(KeyBinding(trigger: trigger, action: .toggleSlots(first, second)))
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
