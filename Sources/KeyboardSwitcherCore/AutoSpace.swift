import Foundation

/// Auto space (issue #10, off by default): a half-width space at the boundary between Chinese and English
/// that a trigger switch creates. Into an English source, before the first letter or digit when the character
/// before the caret is Han; into a Chinese source, before the first letter (the start of pinyin) when that
/// character is an ASCII letter or digit. Pure: the caller reads the character (off the main thread) and posts
/// the keys.
public enum AutoSpace {
    /// Which side of the boundary the switch went to.
    public enum Direction: Equatable, Sendable {
        /// Into a source that types Latin: the space goes after Chinese text.
        case intoLatin
        /// Into a Chinese input method: the space goes after English text or digits. Chinese input methods
        /// see only what they typed themselves, not English typed in another source.
        case intoChinese
    }

    /// What the character before the caret says about the boundary.
    public enum Before: Equatable, Sendable {
        case han
        case asciiLetterOrDigit
        /// A space, punctuation (full or half width) or anything else: no space is added.
        case noSpaceNeeded
        /// The caret is at the start of the text, or nothing could be read.
        case unknown
    }

    public static func classify(_ text: String?) -> Before {
        guard let scalar = text?.unicodeScalars.last else { return .unknown }
        if isHan(scalar) { return .han }
        if isASCIILetter(scalar) || isASCIIDigit(scalar) { return .asciiLetterOrDigit }
        return .noSpaceNeeded
    }

    /// CJK Unified Ideographs, extensions A to F, and the compatibility block.
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2EBEF, 0xF900...0xFAFF, 0x2F800...0x2FA1F: true
        default: false
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private static let chineseLanguages = ["zh", "yue"]
    /// Japanese and Korean typesetting does not put a space between their script and Latin text.
    private static let otherCJKLanguages = ["ja", "ko"]

    private static func speaks(_ source: InputSourceInfo, _ languages: [String]) -> Bool {
        source.languages.contains { language in languages.contains { language == $0 || language.hasPrefix($0 + "-") } }
    }

    /// Which boundary a switch to `source` creates, or nil for a source auto space leaves alone (Japanese, Korean).
    public static func direction(switchingTo source: InputSourceInfo) -> Direction? {
        if speaks(source, chineseLanguages) { return .intoChinese }
        if speaks(source, otherCJKLanguages) { return nil }
        return .intoLatin
    }

    /// Whether the character before the caret asks for a space on this side of the boundary.
    public static func needsSpace(_ direction: Direction, before: Before) -> Bool {
        switch direction {
        case .intoLatin: before == .han
        case .intoChinese: before == .asciiLetterOrDigit
        }
    }

    /// The key typed while armed: the characters it produces and whether Command, Control or Option is held.
    /// Into English a letter or digit; into Chinese only a letter, which starts pinyin (a digit there is typed
    /// as a digit and needs no space after English).
    public static func qualifies(_ direction: Direction, characters: String, commandControlOrOption: Bool) -> Bool {
        guard !commandControlOrOption, characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first else {
            return false
        }
        switch direction {
        case .intoLatin: return isASCIILetter(scalar) || isASCIIDigit(scalar)
        case .intoChinese: return isASCIILetter(scalar)
        }
    }
}

/// One switch's worth of auto space. Armed by a trigger switch, settled by the read of the character before
/// the caret, spent or dropped by the first key.
public struct AutoSpaceState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The read is still running; a key typed now passes without a space (no waiting on the tap).
        case reading(generation: Int, direction: AutoSpace.Direction)
        case spaceBeforeNextKey(AutoSpace.Direction)
    }

    public private(set) var phase: Phase = .idle
    private var generation = 0

    public init() {}

    /// A trigger switch was confirmed. Returns the generation the read must report with.
    public mutating func armed(_ direction: AutoSpace.Direction) -> Int {
        generation &+= 1
        phase = .reading(generation: generation, direction: direction)
        return generation
    }

    /// The read finished. A read from an older arm, or after the first key, is ignored.
    public mutating func read(_ before: AutoSpace.Before, generation: Int) {
        guard case let .reading(current, direction) = phase, current == generation else { return }
        phase = AutoSpace.needsSpace(direction, before: before) ? .spaceBeforeNextKey(direction) : .idle
    }

    /// A key went down. True when a space goes in before it. Any key ends this switch's chance.
    public mutating func keyDown(characters: String, commandControlOrOption: Bool) -> Bool {
        defer { phase = .idle }
        guard case let .spaceBeforeNextKey(direction) = phase else { return false }
        return AutoSpace.qualifies(direction, characters: characters, commandControlOrOption: commandControlOrOption)
    }

    /// A mouse down, an app switch, a focus change, another switch or the setting turning off.
    public mutating func cancel() {
        phase = .idle
    }
}
