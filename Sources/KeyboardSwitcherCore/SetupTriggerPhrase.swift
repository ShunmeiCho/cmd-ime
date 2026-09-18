import Foundation

/// How the setup guide tells the user to fire one trigger, in plain words.
public struct SetupTriggerPhrase: Equatable, Sendable {
    /// "Tap", "Double-tap" or "Press".
    public let verb: String
    /// "Left Command" for a one-shot modifier, "Option + J" for a chord.
    public let keys: String
    /// A one-shot modifier only counts when it is pressed and released by itself.
    public let isAlone: Bool

    public init(trigger: KeyTrigger) {
        switch trigger.kind {
        case .oneShotModifier:
            verb = trigger.gesture == .doubleTap ? "Double-tap" : "Tap"
            keys = Self.readableName(trigger.keyName)
            isAlone = true
        case .keyPress:
            verb = "Press"
            keys = (trigger.modifiers.map(Self.readableName) + [Self.readableName(trigger.keyName)])
                .joined(separator: " + ")
            isAlone = false
        }
    }

    /// "Tap Left Command alone", "Double-tap Right Option alone", "Press Option + J".
    public var instruction: String {
        isAlone ? "\(verb) \(keys) alone" : "\(verb) \(keys)"
    }

    private static func readableName(_ modifier: Modifier) -> String {
        switch modifier {
        case .capsLock: "Caps Lock"
        case .fn: "Fn"
        default: modifier.rawValue.capitalized
        }
    }

    /// "left-command" -> "Left Command", "j" -> "J", "f1" -> "F1", "space" -> "Space".
    /// The minus key is named "-": it has no words to split, so it stays as it is.
    private static func readableName(_ keyName: String) -> String {
        let words = keyName.split(separator: "-")
        return words.isEmpty ? keyName : words.map { $0.capitalized }.joined(separator: " ")
    }
}

public extension KeyTrigger {
    /// A lone Shift tap. Many Chinese and Japanese input methods already use it to
    /// toggle their own modes, so detection never assigns it; only the user can.
    var isOneShotShift: Bool {
        kind == .oneShotModifier && keyName.hasSuffix("shift")
    }
}

/// Which bound slots the user has already fired in the "Try it" step.
public struct SetupTryItProgress: Equatable, Sendable {
    /// Slots that can be tried, in slot order: at least one enabled switch trigger
    /// and an installed input source to switch to.
    public let boundSlots: [InputRole]
    /// Slots with a trigger but no matching input source. Their trigger cannot
    /// switch, so they never count toward completion.
    public let unmatchedSlots: [InputRole]
    /// The bound slots that were fired at least once. Removed slots are ignored.
    public let triedSlots: [InputRole]

    public init(config: SwitcherConfig, sources: [InputSourceInfo], evidence: SetupTriggerEvidence) {
        let tried = evidence.triedSlotIDs(config: config, sources: sources)
        var seen = Set<InputRole>()
        let withTrigger = config.slotTriggers.map(\.slot).filter { seen.insert($0).inserted }
        let matched = Set(withTrigger.filter {
            InputSourceMatcher.bestMatch(for: $0, sources: sources, config: config) != nil
        })
        boundSlots = withTrigger.filter(matched.contains)
        unmatchedSlots = withTrigger.filter { !matched.contains($0) }
        triedSlots = boundSlots.filter(tried.contains)
    }

    /// The first bound slot that was not fired yet.
    public var nextSlot: InputRole? {
        boundSlots.first { !triedSlots.contains($0) }
    }

    /// Every bound slot was fired once. Never true while nothing is bound.
    public var isComplete: Bool {
        !boundSlots.isEmpty && nextSlot == nil
    }
}
