import KeyboardSwitcherCore

extension KeyTrigger {
    /// Presentation only: keep `displayName` canonical for parsing and persistence.
    var localizedDisplayName: String {
        let phrase = SetupTriggerPhrase(trigger: self)
        return kind == .oneShotModifier ? phrase.instruction : phrase.keys
    }
}
