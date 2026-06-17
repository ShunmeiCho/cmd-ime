import Foundation

public enum ShortcutParserError: Error, Equatable, LocalizedError {
    case empty
    case unknownKey(String)
    case missingKey(String)
    case duplicateModifier(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Shortcut is empty."
        case let .unknownKey(key):
            "Unknown key: \(key)."
        case let .missingKey(shortcut):
            "Shortcut needs a non-modifier key: \(shortcut)."
        case let .duplicateModifier(modifier):
            "Duplicate modifier: \(modifier)."
        }
    }
}

public enum ShortcutParser {
    public static func parse(_ rawValue: String) throws -> KeyTrigger {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShortcutParserError.empty
        }

        let compact = normalizeAlias(trimmed)
        if compact.hasPrefix("double-") {
            let suffix = String(compact.dropFirst("double-".count))
            if var oneShot = oneShotModifiers[suffix] {
                oneShot.gesture = .doubleTap
                return oneShot
            }
        }
        if let oneShot = oneShotModifiers[compact] {
            return oneShot
        }

        let parts = trimmed
            .split(separator: "+")
            .map { normalizeAlias(String($0)) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw ShortcutParserError.empty
        }

        if parts.count == 1, modifierAliases[parts[0]] != nil {
            throw ShortcutParserError.missingKey(trimmed)
        }

        var modifiers: [Modifier] = []
        var seenModifiers = Set<Modifier>()
        for token in parts.dropLast() {
            guard let modifier = modifierAliases[token] else {
                throw ShortcutParserError.unknownKey(token)
            }
            guard seenModifiers.insert(modifier).inserted else {
                throw ShortcutParserError.duplicateModifier(token)
            }
            modifiers.append(modifier)
        }

        guard let keyToken = parts.last else {
            throw ShortcutParserError.empty
        }
        guard let key = keyCodes[keyToken] else {
            throw ShortcutParserError.unknownKey(keyToken)
        }

        return KeyTrigger(kind: .keyPress, keyCode: key.code, keyName: key.name, modifiers: modifiers)
    }

    private static func normalizeAlias(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "⌘", with: "command")
            .replacingOccurrences(of: "⌥", with: "option")
            .replacingOccurrences(of: "⌃", with: "control")
            .replacingOccurrences(of: "⇧", with: "shift")
            .replacingOccurrences(of: "⇪", with: "caps-lock")
    }
}

private let oneShotModifiers: [String: KeyTrigger] = [
    "left-command": KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
    "left-cmd": KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
    "lcommand": KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
    "lcmd": KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
    "right-command": KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
    "right-cmd": KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
    "rcommand": KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
    "rcmd": KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
    "left-option": KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option"),
    "left-alt": KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option"),
    "loption": KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option"),
    "lalt": KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option"),
    "right-option": KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option"),
    "right-alt": KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option"),
    "roption": KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option"),
    "ralt": KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option"),
    "left-control": KeyTrigger(kind: .oneShotModifier, keyCode: 59, keyName: "left-control"),
    "left-ctrl": KeyTrigger(kind: .oneShotModifier, keyCode: 59, keyName: "left-control"),
    "right-control": KeyTrigger(kind: .oneShotModifier, keyCode: 62, keyName: "right-control"),
    "right-ctrl": KeyTrigger(kind: .oneShotModifier, keyCode: 62, keyName: "right-control"),
    "left-shift": KeyTrigger(kind: .oneShotModifier, keyCode: 56, keyName: "left-shift"),
    "lshift": KeyTrigger(kind: .oneShotModifier, keyCode: 56, keyName: "left-shift"),
    "right-shift": KeyTrigger(kind: .oneShotModifier, keyCode: 60, keyName: "right-shift"),
    "rshift": KeyTrigger(kind: .oneShotModifier, keyCode: 60, keyName: "right-shift"),
    // Caps Lock is intentionally not a one-shot trigger: its latch semantics cannot be
    // driven by the tap/double-tap model without corrupting the user's Caps Lock state.
]

private let modifierAliases: [String: Modifier] = [
    "command": .command,
    "cmd": .command,
    "meta": .command,
    "option": .option,
    "opt": .option,
    "alt": .option,
    "control": .control,
    "ctrl": .control,
    "ctl": .control,
    "shift": .shift,
    "fn": .fn,
    "caps-lock": .capsLock,
    "capslock": .capsLock,
]

private struct KeyCodeAlias {
    var code: Int
    var name: String
}

private let keyCodes: [String: KeyCodeAlias] = [
    "a": KeyCodeAlias(code: 0, name: "a"),
    "s": KeyCodeAlias(code: 1, name: "s"),
    "d": KeyCodeAlias(code: 2, name: "d"),
    "f": KeyCodeAlias(code: 3, name: "f"),
    "h": KeyCodeAlias(code: 4, name: "h"),
    "g": KeyCodeAlias(code: 5, name: "g"),
    "z": KeyCodeAlias(code: 6, name: "z"),
    "x": KeyCodeAlias(code: 7, name: "x"),
    "c": KeyCodeAlias(code: 8, name: "c"),
    "v": KeyCodeAlias(code: 9, name: "v"),
    "b": KeyCodeAlias(code: 11, name: "b"),
    "q": KeyCodeAlias(code: 12, name: "q"),
    "w": KeyCodeAlias(code: 13, name: "w"),
    "e": KeyCodeAlias(code: 14, name: "e"),
    "r": KeyCodeAlias(code: 15, name: "r"),
    "y": KeyCodeAlias(code: 16, name: "y"),
    "t": KeyCodeAlias(code: 17, name: "t"),
    "1": KeyCodeAlias(code: 18, name: "1"),
    "2": KeyCodeAlias(code: 19, name: "2"),
    "3": KeyCodeAlias(code: 20, name: "3"),
    "4": KeyCodeAlias(code: 21, name: "4"),
    "6": KeyCodeAlias(code: 22, name: "6"),
    "5": KeyCodeAlias(code: 23, name: "5"),
    "=": KeyCodeAlias(code: 24, name: "="),
    "9": KeyCodeAlias(code: 25, name: "9"),
    "7": KeyCodeAlias(code: 26, name: "7"),
    "-": KeyCodeAlias(code: 27, name: "-"),
    "8": KeyCodeAlias(code: 28, name: "8"),
    "0": KeyCodeAlias(code: 29, name: "0"),
    "]": KeyCodeAlias(code: 30, name: "]"),
    "o": KeyCodeAlias(code: 31, name: "o"),
    "u": KeyCodeAlias(code: 32, name: "u"),
    "[": KeyCodeAlias(code: 33, name: "["),
    "i": KeyCodeAlias(code: 34, name: "i"),
    "p": KeyCodeAlias(code: 35, name: "p"),
    "return": KeyCodeAlias(code: 36, name: "return"),
    "enter": KeyCodeAlias(code: 36, name: "return"),
    "l": KeyCodeAlias(code: 37, name: "l"),
    "j": KeyCodeAlias(code: 38, name: "j"),
    "'": KeyCodeAlias(code: 39, name: "'"),
    "k": KeyCodeAlias(code: 40, name: "k"),
    ";": KeyCodeAlias(code: 41, name: ";"),
    "\\": KeyCodeAlias(code: 42, name: "\\"),
    ",": KeyCodeAlias(code: 43, name: ","),
    "/": KeyCodeAlias(code: 44, name: "/"),
    "n": KeyCodeAlias(code: 45, name: "n"),
    "m": KeyCodeAlias(code: 46, name: "m"),
    ".": KeyCodeAlias(code: 47, name: "."),
    "tab": KeyCodeAlias(code: 48, name: "tab"),
    "space": KeyCodeAlias(code: 49, name: "space"),
    "`": KeyCodeAlias(code: 50, name: "`"),
    "delete": KeyCodeAlias(code: 51, name: "delete"),
    "backspace": KeyCodeAlias(code: 51, name: "delete"),
    "escape": KeyCodeAlias(code: 53, name: "escape"),
    "esc": KeyCodeAlias(code: 53, name: "escape"),
    "left": KeyCodeAlias(code: 123, name: "left"),
    "arrow-left": KeyCodeAlias(code: 123, name: "left"),
    "right": KeyCodeAlias(code: 124, name: "right"),
    "arrow-right": KeyCodeAlias(code: 124, name: "right"),
    "down": KeyCodeAlias(code: 125, name: "down"),
    "arrow-down": KeyCodeAlias(code: 125, name: "down"),
    "up": KeyCodeAlias(code: 126, name: "up"),
    "arrow-up": KeyCodeAlias(code: 126, name: "up"),
    "f1": KeyCodeAlias(code: 122, name: "f1"),
    "f2": KeyCodeAlias(code: 120, name: "f2"),
    "f3": KeyCodeAlias(code: 99, name: "f3"),
    "f4": KeyCodeAlias(code: 118, name: "f4"),
    "f5": KeyCodeAlias(code: 96, name: "f5"),
    "f6": KeyCodeAlias(code: 97, name: "f6"),
    "f7": KeyCodeAlias(code: 98, name: "f7"),
    "f8": KeyCodeAlias(code: 100, name: "f8"),
    "f9": KeyCodeAlias(code: 101, name: "f9"),
    "f10": KeyCodeAlias(code: 109, name: "f10"),
    "f11": KeyCodeAlias(code: 103, name: "f11"),
    "f12": KeyCodeAlias(code: 111, name: "f12"),
]
