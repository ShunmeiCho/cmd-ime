import Foundation

/// A presentation category; bindings keep their existing JSON representation.
public enum SlotTriggerCategory: String, CaseIterable, Sendable {
    case single
    case double
    case shortcut

    public func matches(_ trigger: KeyTrigger) -> Bool {
        switch self {
        case .single: trigger.kind == .oneShotModifier && trigger.gesture == .tap
        case .double: trigger.kind == .oneShotModifier && trigger.gesture == .doubleTap
        case .shortcut: trigger.kind == .keyPress && trigger.gesture == .tap
            && !Set(trigger.modifiers).subtracting(Modifier.latching).isEmpty
        }
    }
}

public enum SlotTriggerCategoryError: Error, Equatable, LocalizedError, Sendable {
    case mismatchedTrigger(SlotTriggerCategory)
    case conflictingBinding(KeyBinding)

    public var errorDescription: String? {
        switch self {
        case let .mismatchedTrigger(category): "Choose a trigger matching the \(category.rawValue) category."
        case let .conflictingBinding(binding): "The trigger \(binding.trigger.displayName) is already assigned."
        }
    }
}

extension SwitcherConfig {
    /// Returns the first enabled switch binding in this category, never a remap.
    public func binding(for role: InputRole, category: SlotTriggerCategory) -> KeyBinding? {
        bindings.first {
            $0.enabled && $0.action.type == .switchInputSource
                && $0.action.role == role && category.matches($0.trigger)
        }
    }

    /// Replaces only this slot/category, or clears it when trigger is nil.
    /// Existing category entries are collapsed at their first position. Explicit
    /// recording enables the replacement, including a previously disabled entry.
    /// Other bindings and all non-binding configuration are unchanged.
    public func replacingSwitchBinding(
        for role: InputRole,
        category: SlotTriggerCategory,
        with trigger: KeyTrigger?
    ) throws -> SwitcherConfig {
        guard slot(role) != nil else { throw SlotError.unknownSlot(role) }
        if let trigger, !category.matches(trigger) {
            throw SlotTriggerCategoryError.mismatchedTrigger(category)
        }
        let indices = bindings.indices.filter {
            bindings[$0].action.type == .switchInputSource
                && bindings[$0].action.role == role && category.matches(bindings[$0].trigger)
        }
        var result = self
        let removed = Set(indices)
        result.bindings = bindings.enumerated().compactMap { removed.contains($0.offset) ? nil : $0.element }
        guard let trigger else { return result }

        do {
            // Legacy conflict helpers reserve an entire physical modifier. Filter
            // only the explicitly compatible single/double pair before using them.
            for occupant in result.bindings where occupant.enabled {
                if trigger.kind == .oneShotModifier,
                   occupant.trigger.kind == .oneShotModifier,
                   trigger.gesture != occupant.trigger.gesture { continue }
                var probe = result
                var checked = occupant
                // Do not exclude a different category owned by this same slot.
                if checked.action.type == .switchInputSource && checked.action.role == role {
                    checked.action = BindingAction(type: .disable)
                }
                probe.bindings = [checked]
                if probe.conflictingBinding(for: trigger, excluding: role) != nil
                    || probe.oneShotModifierConflict(for: trigger, excluding: role) != nil {
                    throw SlotTriggerCategoryError.conflictingBinding(occupant)
                }
            }
        }
        result.bindings.insert(
            KeyBinding(trigger: trigger, action: .switchInputSource(role), enabled: true),
            at: indices.first ?? result.bindings.count
        )
        return result
    }
}
