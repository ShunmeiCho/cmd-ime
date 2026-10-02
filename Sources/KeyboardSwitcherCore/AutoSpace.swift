import Foundation

/// Auto space (issue #10, off by default): after a trigger switch into a Latin slot, a half-width space
/// before the first letter or digit typed when the character before the caret is Han. Pure: the caller reads
/// the character (off the main thread) and posts the keys.
public enum AutoSpace {
    /// What the character before the caret says about the boundary.
    public enum Before: Equatable, Sendable {
        case han
        /// A space, full-width punctuation, Latin, a digit or anything else: no space is added.
        case noSpaceNeeded
        /// The caret is at the start of the text, or nothing could be read.
        case unknown
    }

    public static func classify(_ text: String?) -> Before {
        guard let scalar = text?.unicodeScalars.last else { return .unknown }
        return isHan(scalar) ? .han : .noSpaceNeeded
    }

    /// CJK Unified Ideographs, extensions A to F, and the compatibility block.
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2EBEF, 0xF900...0xFAFF, 0x2F800...0x2FA1F: true
        default: false
        }
    }

    /// Whether a switch to `source` arms auto space: a source that types Latin, not a CJK input method.
    public static func arms(switchingTo source: InputSourceInfo) -> Bool {
        let cjk = ["zh", "ja", "ko", "yue"]
        return !source.languages.contains { language in cjk.contains { language == $0 || language.hasPrefix($0 + "-") } }
    }

    /// The key typed while armed: the characters it produces and whether Command, Control or Option is held.
    public static func qualifies(characters: String, commandControlOrOption: Bool) -> Bool {
        guard !commandControlOrOption, characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first else {
            return false
        }
        return scalar.isASCII && (CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar))
    }
}

/// One switch's worth of auto space. Armed by a trigger switch, settled by the read of the character before
/// the caret, spent or dropped by the first key.
public struct AutoSpaceState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The read is still running; a key typed now passes without a space (no waiting on the tap).
        case reading(generation: Int)
        case spaceBeforeNextKey
    }

    public private(set) var phase: Phase = .idle
    private var generation = 0

    public init() {}

    /// A trigger switch into a Latin slot was confirmed. Returns the generation the read must report with.
    public mutating func armed() -> Int {
        generation &+= 1
        phase = .reading(generation: generation)
        return generation
    }

    /// The read finished. A read from an older arm, or after the first key, is ignored.
    public mutating func read(_ before: AutoSpace.Before, generation: Int) {
        guard phase == .reading(generation: generation) else { return }
        phase = before == .han ? .spaceBeforeNextKey : .idle
    }

    /// A key went down. True when a space goes in before it. Any key ends this switch's chance.
    public mutating func keyDown(characters: String, commandControlOrOption: Bool) -> Bool {
        defer { phase = .idle }
        return phase == .spaceBeforeNextKey && AutoSpace.qualifies(characters: characters, commandControlOrOption: commandControlOrOption)
    }

    /// A mouse down, an app switch, a focus change, another switch or the setting turning off.
    public mutating func cancel() {
        phase = .idle
    }
}
