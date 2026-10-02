import Foundation

/// The mark a shell writes into its terminal tab's title so that CmdIME can tell which terminal
/// device that tab is: the number of `/dev/ttysNNN`, in zero-width characters nobody sees.
///
/// Only U+200B and U+200C are used: both were measured to reach Accessibility intact through a
/// Ghostty tab title (2026-10-03). The mark is a fixed start pattern, sixteen bits (U+200B is 0,
/// U+200C is 1, most significant first) and a fixed end pattern. Anything else in a title is
/// ignored; a title with no complete mark names no device.
///
/// The mark is read and written as Unicode scalars, not Characters: U+200C extends the grapheme
/// before it, so a Character view would fold the mark into its neighbours.
public enum TerminalTitleMarker {
    private static let zero: Unicode.Scalar = "\u{200B}"
    private static let one: Unicode.Scalar = "\u{200C}"
    private static let start: [Unicode.Scalar] = [one, one, one, zero]
    private static let end: [Unicode.Scalar] = [zero, one, one, one]
    private static let bitCount = 16
    private static let devicePrefix = "ttys"
    private static let devicePath = "/dev/"

    /// The mark for a device such as `/dev/ttys009` or `ttys009`; nil for any other name.
    public static func mark(forDevice device: String) -> String? {
        guard let number = deviceNumber(device) else { return nil }
        let bits = (0..<bitCount).reversed().map { (number >> $0) & 1 == 1 ? one : zero }
        var mark = String.UnicodeScalarView()
        mark.append(contentsOf: start + bits + end)
        return String(mark)
    }

    /// The device (`ttys009`) a title's last complete mark names, or nil.
    public static func device(inTitle title: String) -> String? {
        let characters = Array(title.unicodeScalars)
        let width = start.count + bitCount + end.count
        guard characters.count >= width else { return nil }
        for offset in stride(from: characters.count - width, through: 0, by: -1) {
            guard Array(characters[offset..<offset + start.count]) == start,
                  Array(characters[offset + start.count + bitCount..<offset + width]) == end else { continue }
            var number = 0
            for character in characters[offset + start.count..<offset + start.count + bitCount] {
                guard character == zero || character == one else { return nil }
                number = number << 1 | (character == one ? 1 : 0)
            }
            return devicePrefix + String(format: "%03d", number)
        }
        return nil
    }

    private static func deviceNumber(_ device: String) -> Int? {
        let name = device.hasPrefix(devicePath) ? String(device.dropFirst(devicePath.count)) : device
        guard name.hasPrefix(devicePrefix) else { return nil }
        let digits = name.dropFirst(devicePrefix.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let number = Int(digits), number < 1 << bitCount else { return nil }
        return number
    }
}
