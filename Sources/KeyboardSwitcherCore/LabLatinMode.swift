import Foundation

/// How the lab leaves an input method in its own latin mode before switching away from it.
///
/// An input method can be selected while its own mode is latin: azooKey after the alphanumeric
/// key, a pinyin input method after Shift. The menu bar then names the input method while keys
/// still come out latin, which is how azooKey failed on a real machine on 2026-09-24 while every
/// earlier lab run passed, because the lab only ever found it in kana mode. This puts the input
/// method in that state first, so the switch under test has to get it out again.
public struct LabLatinMode: Equatable, Sendable {
    /// The key that moves this input method to its latin mode.
    public let keyCode: Int
    /// A modifier is tapped as a flags change; a plain key is pressed.
    public let isModifier: Bool

    /// `kVK_JIS_Eisu`: sets a Japanese input method to alphanumeric; recognised on every keyboard.
    public static let japanese = LabLatinMode(keyCode: 102, isModifier: false)
    /// Left Shift, which most pinyin input methods use to toggle their English mode. A toggle
    /// from English goes back to Chinese; the probe catches that and the attempt is repeated.
    public static let pinyin = LabLatinMode(keyCode: 56, isModifier: true)

    /// The probe typed to check the mode: `a` then Space. Latin mode leaves `a` and a space;
    /// kana mode turns it into あ, pinyin mode commits a Han candidate.
    public static let probeKeyCodes = [0, LabExpectation.space]

    /// nil when the lab knows no way to put this source in a latin mode, including plain layouts.
    public static func forSource(id: String) -> LabLatinMode? {
        // By the text the source produces, so an unverified row gets the same treatment.
        switch LabExpectation.forSource(id: id)?.acceptedScalarRanges {
        case LabExpectation.kana?: japanese
        case LabExpectation.han?: pinyin
        default: nil
        }
    }

    /// True when the probe came out as latin letters only, so the input method is in latin mode.
    public static func holds(probeText text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("a") && trimmed.unicodeScalars.allSatisfy { $0.isASCII }
    }
}
