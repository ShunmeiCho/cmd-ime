import Foundation

/// Peek (CONTEXT.md): a trigger that shows the bubble for the current input source without
/// switching. It is an ordinary binding whose action is `showIndicator`; at most one exists.
public enum PeekBindingError: Error, Equatable, LocalizedError, Sendable {
    case reservedByMacOS(KeyTrigger)
    case conflictingBinding(KeyBinding)

    public var errorDescription: String? {
        switch self {
        case let .reservedByMacOS(trigger): CoreLocalization.text("%@ is reserved by macOS input source switching", String(describing: trigger.displayName))
        case let .conflictingBinding(binding): CoreLocalization.text("The trigger %@ is already assigned.", String(describing: binding.trigger.displayName))
        }
    }
}

extension SwitcherConfig {
    public static let peekDisplayName = CoreLocalization.text("Show Current Input Source")

    public var peekBinding: KeyBinding? {
        bindings.first { $0.enabled && $0.action.type == .showIndicator }
    }

    /// Replaces the peek trigger, or removes it when `trigger` is nil. Refuses a trigger another
    /// enabled binding already answers to, with the same rule the slot board uses: a single and a
    /// double tap of one modifier key are different triggers, anything else on that key is not.
    public func replacingPeekBinding(with trigger: KeyTrigger?) throws(PeekBindingError) -> SwitcherConfig {
        var result = self
        result.bindings.removeAll { $0.action.type == .showIndicator }
        guard let trigger else { return result }
        if trigger.isReservedMacInputSourceShortcut {
            throw .reservedByMacOS(trigger)
        }
        if let occupant = result.bindings.first(where: { $0.enabled && Self.triggers($0.trigger, collideWith: trigger) }) {
            throw .conflictingBinding(occupant)
        }
        result.bindings.append(KeyBinding(trigger: trigger, action: .showIndicator))
        return result
    }

    /// The CLI's `bind <trigger> peek`: like `bind` for a slot, it takes the trigger from whatever
    /// had it. Returns the bindings it displaced so the caller can say so.
    public mutating func upsertPeekBinding(trigger: KeyTrigger) -> [KeyBinding] {
        let displaced = bindings.filter { $0.trigger == trigger && $0.action.type != .showIndicator }
        bindings.removeAll { $0.trigger == trigger || $0.action.type == .showIndicator }
        bindings.append(KeyBinding(trigger: trigger, action: .showIndicator))
        return displaced
    }

    /// What a conflict message calls the owner of `binding`.
    public func ownerDescription(of binding: KeyBinding) -> String {
        switch binding.action.type {
        case .switchInputSource: binding.action.role.map { displayName(for: $0) } ?? CoreLocalization.text("another binding")
        case .sendKey: CoreLocalization.text("a key remap")
        case .showIndicator: Self.peekDisplayName
        case .disable: CoreLocalization.text("another binding")
        }
    }

    private static func triggers(_ existing: KeyTrigger, collideWith candidate: KeyTrigger) -> Bool {
        guard existing.keyCode == candidate.keyCode else { return false }
        if existing.kind == .oneShotModifier, candidate.kind == .oneShotModifier {
            return existing.gesture == candidate.gesture
        }
        if existing.kind == .oneShotModifier || candidate.kind == .oneShotModifier { return true }
        return existing.gesture == candidate.gesture && Set(existing.modifiers) == Set(candidate.modifiers)
    }
}
