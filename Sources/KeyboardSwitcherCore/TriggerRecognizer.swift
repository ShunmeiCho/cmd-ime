import Foundation

/// A recording-session draft, independent of event delivery, timers and persistence.
public struct TriggerRecognizer: Sendable {
    public enum Intent: Equatable, Sendable {
        case chord(KeyTrigger)
        case tap(String)
        case doubleTap(String)
        case cancel
        case commit
        case clear
    }

    /// The parser is the sole source of physical modifier codes and canonical names.
    public static let modifierTriggers: [Int: KeyTrigger] = {
        var result: [Int: KeyTrigger] = [:]
        for modifier in Modifier.allCases {
            for side in ["left", "right"] {
                if let trigger = try? ShortcutParser.parse("\(side)-\(modifier.rawValue)"),
                   trigger.kind == .oneShotModifier {
                    result[trigger.keyCode] = trigger
                }
            }
        }
        return result
    }()

    private static let modifierFamilies: [Int: Modifier] = {
        var result: [Int: Modifier] = [:]
        for modifier in Modifier.allCases {
            for side in ["left", "right"] {
                if let trigger = try? ShortcutParser.parse("\(side)-\(modifier.rawValue)"),
                   modifierTriggers[trigger.keyCode] != nil {
                    result[trigger.keyCode] = modifier
                }
            }
        }
        return result
    }()

    public private(set) var draft: KeyTrigger?
    public private(set) var pressedModifierKeyCodes: Set<Int>
    private var pressedKeys: Set<Int> = []
    private var tapCandidate: Int?
    private var pendingTap: (code: Int, timestamp: TimeInterval)?

    /// Keys already held at session start are tracked but never eligible for a tap.
    public init(existingTrigger: KeyTrigger? = nil, heldModifierKeyCodes: Set<Int> = []) {
        draft = existingTrigger
        pressedModifierKeyCodes = heldModifierKeyCodes.intersection(Self.modifierTriggers.keys)
    }

    public mutating func keyDown(
        keyCode: Int, keyName: String, modifiers: Set<Modifier>, timestamp: TimeInterval
    ) -> Intent? {
        let modifiers = modifiers.subtracting(Modifier.latching)
        if let family = Self.modifierFamilies[keyCode] {
            // Repeated downs must not resurrect a candidate poisoned by a chord.
            guard !pressedModifierKeyCodes.contains(keyCode) else { return nil }
            let isolated = pressedModifierKeyCodes.isEmpty && pressedKeys.isEmpty
                && modifiers.subtracting([family]).isEmpty
            pressedModifierKeyCodes.insert(keyCode)
            if isolated {
                tapCandidate = keyCode
            } else {
                invalidateTaps()
            }
            return nil
        }

        pressedKeys.insert(keyCode)
        invalidateTaps()
        if modifiers.isEmpty {
            switch keyCode {
            case 53: return .cancel
            case 36, 76: return .commit
            case 51, 117:
                guard draft != nil else { return nil }
                draft = nil
                return .clear
            default: break
            }
        }
        let trigger = KeyTrigger(kind: .keyPress, keyCode: keyCode,
                                 keyName: keyName, modifiers: Array(modifiers))
        draft = trigger
        return .chord(trigger)
    }

    public mutating func keyUp(
        keyCode: Int, keyName: String, modifiers: Set<Modifier>, timestamp: TimeInterval
    ) -> Intent? {
        let modifiers = modifiers.subtracting(Modifier.latching)
        guard var trigger = Self.modifierTriggers[keyCode] else {
            pressedKeys.remove(keyCode)
            return nil
        }
        guard pressedModifierKeyCodes.remove(keyCode) != nil else { return nil }
        guard tapCandidate == keyCode, pressedModifierKeyCodes.isEmpty, modifiers.isEmpty else {
            invalidateTaps()
            return nil
        }
        tapCandidate = nil
        if let pendingTap, pendingTap.code == keyCode,
           timestamp >= pendingTap.timestamp,
           timestamp - pendingTap.timestamp <= OneShotModifierState.doubleTapWindow {
            self.pendingTap = nil
            trigger.gesture = .doubleTap
            draft = trigger
            return .doubleTap(trigger.keyName)
        }
        pendingTap = (keyCode, timestamp)
        draft = trigger
        return .tap(trigger.keyName)
    }

    /// Aggregate flags cannot distinguish sides. A known held physical code is
    /// releasing even when its family flag remains set because the other side is held.
    public mutating func flagsChanged(
        keyCode: Int, modifiers: Set<Modifier>, timestamp: TimeInterval
    ) -> Intent? {
        let modifiers = modifiers.subtracting(Modifier.latching)
        guard let trigger = Self.modifierTriggers[keyCode],
              let family = Self.modifierFamilies[keyCode] else {
            invalidateTaps()
            return nil
        }
        if pressedModifierKeyCodes.contains(keyCode) {
            return keyUp(keyCode: keyCode, keyName: trigger.keyName,
                         modifiers: modifiers, timestamp: timestamp)
        }
        guard modifiers.contains(family) else { return nil }
        return keyDown(keyCode: keyCode, keyName: trigger.keyName,
                       modifiers: modifiers, timestamp: timestamp)
    }

    private mutating func invalidateTaps() {
        tapCandidate = nil
        pendingTap = nil
    }
}
