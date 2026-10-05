import Foundation

/// A key chord as macOS stores it for a system shortcut: one key plus an exact set of modifiers,
/// either side of each.
public struct SystemChord: Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: Set<Modifier>

    public init(keyCode: Int, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The two macOS input source shortcuts (Keyboard Shortcuts > Input Sources): "Select the previous
/// input source" (id 60, Control+Space) and "Select next source in Input menu" (id 61,
/// Control+Option+Space). macOS takes these chords before any app sees them, so a trigger on one is
/// refused, but only while the shortcut is on: a user who turned it off or moved it to another chord
/// gets the old one back.
public enum MacInputSourceShortcuts {
    static let domain = "com.apple.symbolichotkeys"
    static let hotKeysKey = "AppleSymbolicHotKeys"
    static let selectPreviousID = "60"
    static let selectNextID = "61"
    /// The key code macOS stores for a shortcut whose chord was cleared.
    static let noKeyCode = 65535

    static let spaceKeyCode = 49
    public static let defaults: [SystemChord] = [
        SystemChord(keyCode: spaceKeyCode, modifiers: [.control]),
        SystemChord(keyCode: spaceKeyCode, modifiers: [.control, .option]),
    ]

    /// `NSEvent.ModifierFlags` bits as stored in the shortcut's third parameter.
    static let modifierMasks: [(Modifier, Int)] = [
        (.capsLock, 0x10000),
        (.shift, 0x20000),
        (.control, 0x40000),
        (.option, 0x80000),
        (.command, 0x100000),
        (.fn, 0x800000),
    ]

    /// Reads the stored `AppleSymbolicHotKeys` dictionary. A missing dictionary or entry means the
    /// shortcut was never changed, so it is on with its default chord; an entry with `enabled = 0`
    /// is off; an enabled entry uses its stored key code and modifier mask.
    static func enabledChords(hotKeys: Any?) -> [SystemChord] {
        let entries = hotKeys as? [String: Any] ?? [:]
        return zip([selectPreviousID, selectNextID], defaults).compactMap { id, fallback in
            chord(entry: entries[id], fallback: fallback)
        }
    }

    private static func chord(entry: Any?, fallback: SystemChord) -> SystemChord? {
        guard let entry = entry as? [String: Any] else {
            return fallback
        }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue {
            return nil
        }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 else {
            return fallback
        }
        let keyCode = parameters[1].intValue
        if keyCode == noKeyCode {
            return nil
        }
        let mask = parameters[2].intValue
        let modifiers = Set(modifierMasks.filter { mask & $0.1 != 0 }.map(\.0))
        return SystemChord(keyCode: keyCode, modifiers: modifiers)
    }

    /// The chords macOS takes for input source switching right now. Elsewhere, the defaults.
    public static func current() -> [SystemChord] {
        #if os(macOS)
        let domain = Self.domain as CFString
        CFPreferencesAppSynchronize(domain)
        return enabledChords(hotKeys: CFPreferencesCopyAppValue(hotKeysKey as CFString, domain))
        #else
        return defaults
        #endif
    }
}

extension KeyTrigger {
    /// Whether macOS takes this trigger as one of `chords`. Sides do not matter: the system shortcut
    /// answers to either side of each modifier.
    public func isReserved(by chords: [SystemChord]) -> Bool {
        kind == .keyPress && chords.contains(SystemChord(keyCode: keyCode, modifiers: Set(modifiers)))
    }

    /// Whether macOS currently takes this trigger for input source switching.
    public var isReservedMacInputSourceShortcut: Bool {
        isReserved(by: MacInputSourceShortcuts.current())
    }
}
