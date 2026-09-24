import Foundation

/// What the reliability lab types into a real text client for one input source, and what the
/// committed text has to look like for the switch to count as working.
///
/// Rows are keyed by input source id prefix, not by language: every Chinese input source reports
/// `zh` while pinyin, bopomofo, cangjie and each Rime schema need different keys and produce
/// different text. An id that matches no row is reported, never guessed at.
public struct LabExpectation: Equatable, Sendable {
    /// Virtual keycodes to send, in order, before the commit key.
    public let keyCodes: [Int]
    /// The letters those keycodes carry on a US ANSI layout, for the report.
    public let letters: String
    /// Sent after the letters so the input method commits; nil for plain keyboard layouts.
    public let commitKeyCode: Int?
    /// The committed text passes when at least one character falls in one of these ranges.
    public let acceptedScalarRanges: [ClosedRange<UInt32>]
    /// A row nobody has run on a real machine yet. Unverified rows are reported as unjudged.
    public let isVerified: Bool

    public init(
        keyCodes: [Int],
        letters: String,
        commitKeyCode: Int?,
        acceptedScalarRanges: [ClosedRange<UInt32>],
        isVerified: Bool
    ) {
        self.keyCodes = keyCodes
        self.letters = letters
        self.commitKeyCode = commitKeyCode
        self.acceptedScalarRanges = acceptedScalarRanges
        self.isVerified = isVerified
    }

    public static let space = 49
    public static let returnKey = 36

    /// `nihao` on a US ANSI layout.
    static let pinyinKeys = [45, 34, 4, 0, 31]
    /// `aiu`.
    static let kanaKeys = [0, 34, 32]
    /// Han, including the extension A block Rime and others reach for.
    static let han: [ClosedRange<UInt32>] = [0x4E00...0x9FFF, 0x3400...0x4DBF]
    static let kana: [ClosedRange<UInt32>] = [0x3040...0x30FF, 0x4E00...0x9FFF]
    static let hangul: [ClosedRange<UInt32>] = [0xAC00...0xD7A3]
    /// Printable ASCII, which is what a plain keyboard layout must produce.
    static let latin: [ClosedRange<UInt32>] = [0x0020...0x007E]

    public static let pinyin = LabExpectation(
        keyCodes: pinyinKeys, letters: "nihao", commitKeyCode: space,
        acceptedScalarRanges: han, isVerified: true
    )
    public static let japanese = LabExpectation(
        keyCodes: kanaKeys, letters: "aiu", commitKeyCode: returnKey,
        acceptedScalarRanges: kana, isVerified: true
    )
    public static let korean = LabExpectation(
        keyCodes: [2, 40, 1], letters: "dks", commitKeyCode: space,
        acceptedScalarRanges: hangul, isVerified: false
    )
    /// Pinyin as the lab types it, for a source nobody has run the lab on yet.
    public static let unverifiedPinyin = LabExpectation(
        keyCodes: pinyinKeys, letters: "nihao", commitKeyCode: space,
        acceptedScalarRanges: han, isVerified: false
    )
    public static let keyboardLayout = LabExpectation(
        keyCodes: pinyinKeys, letters: "nihao", commitKeyCode: nil,
        acceptedScalarRanges: latin, isVerified: true
    )

    /// Longest matching prefix wins, so a specific mode beats its parent bundle.
    static let table: [(prefix: String, expectation: LabExpectation)] = [
        ("com.apple.keylayout.", keyboardLayout),
        ("com.apple.inputmethod.SCIM.ITABC", pinyin),
        ("com.tencent.inputmethod.wetype.pinyin", pinyin),
        ("com.bytedance.inputmethod.doubaoime.pinyin", unverifiedPinyin),
        ("im.rime.inputmethod.Squirrel.Hans", pinyin),
        ("im.rime.inputmethod.Squirrel.Hant", pinyin),
        ("dev.ensan.inputmethod.azooKeyMac.Japanese", japanese),
        ("com.google.inputmethod.Japanese.base", japanese),
        ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", japanese),
        ("com.apple.inputmethod.Korean.2SetKorean", korean),
    ]

    public static func forSource(id: String) -> LabExpectation? {
        table
            .filter { id.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .expectation
    }

    /// True when the text holds at least one character this expectation accepts.
    public func accepts(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            acceptedScalarRanges.contains { $0.contains(scalar.value) }
        }
    }
}
