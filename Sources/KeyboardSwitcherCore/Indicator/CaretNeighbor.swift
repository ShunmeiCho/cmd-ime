import Foundation

/// Where the caret is when an app gives no rect for the caret itself but does for the characters next to it
/// (many web fields answer an empty rect for a zero-length range). Pure geometry over accessibility rects.
public enum CaretNeighbor {
    public enum Side: Equatable, Sendable {
        /// The character before the caret: the caret is at its trailing edge.
        case before
        /// The character after the caret: the caret is at its leading edge.
        case after
    }

    public struct Candidate: Equatable, Sendable {
        public let location: Int
        public let side: Side
    }

    public struct Rect: Equatable, Sendable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            (self.x, self.y, self.width, self.height) = (x, y, width, height)
        }
    }

    /// One neighbor as the app reported it: its rect and the character itself.
    public struct Neighbor: Equatable, Sendable {
        public let rect: Rect
        public let text: String?
        public init(rect: Rect, text: String?) { (self.rect, self.text) = (rect, text) }
    }

    /// The characters to ask about: before the caret (when there is one) and after it.
    public static func candidates(caretLocation: Int) -> [Candidate] {
        (caretLocation > 0 ? [Candidate(location: caretLocation - 1, side: .before)] : [])
            + [Candidate(location: caretLocation, side: .after)]
    }

    /// A zero-width caret rect at the character's trailing or leading edge, as tall as the character.
    public static func caret(fromCharacter rect: Rect, side: Side) -> Rect {
        Rect(x: side == .before ? rect.x + rect.width : rect.x, y: rect.y, width: 0, height: rect.height)
    }

    /// What asking about one side gave.
    public enum Lookup: Equatable, Sendable {
        case found(Neighbor)
        /// There is no character on that side (the start or the end of the text).
        case none
        /// The app did not answer, or the budget ran out: nothing is known about that side.
        case unknown
    }

    /// The caret from what the neighbors say, or nil when it cannot be told (review A2):
    /// - a neighbor whose text is unknown or right-to-left, where the logical edge may be on the other side;
    /// - two neighbors on different lines (a soft wrap), where the caret could be at either;
    /// - one side unknown, which could hide such a wrap.
    public static func caret(before: Lookup, after: Lookup) -> Rect? {
        switch (before, after) {
        case let (.found(before), .found(after)):
            guard isLeftToRight(before), isLeftToRight(after) else { return nil }
            let lineHeight = min(before.rect.height, after.rect.height)
            guard abs(before.rect.y - after.rect.y) < lineHeight / 2 else { return nil }
            return caret(fromCharacter: before.rect, side: .before)
        case let (.found(before), .none):
            return isLeftToRight(before) ? caret(fromCharacter: before.rect, side: .before) : nil
        case let (.none, .found(after)):
            return isLeftToRight(after) ? caret(fromCharacter: after.rect, side: .after) : nil
        default:
            return nil
        }
    }

    /// A field taller than this is a multi-line editor: its leading edge says nothing about where the caret is.
    public static let maxFieldHeight = 120.0
    private static let fieldInset = 6.0
    private static let fieldLineHeight = 18.0

    /// A caret at the field's leading edge, centred on a line height; nil for a field too tall or empty in size.
    public static func caret(inField field: Rect) -> Rect? {
        guard field.width > 0, field.height > 0, field.height <= maxFieldHeight else { return nil }
        let height = min(field.height, fieldLineHeight)
        return Rect(x: field.x + min(fieldInset, field.width / 2), y: field.y + (field.height - height) / 2, width: 0, height: height)
    }

    /// Known text that is not right-to-left. Unknown text is not taken as left-to-right.
    static func isLeftToRight(_ neighbor: Neighbor) -> Bool {
        neighbor.text?.isEmpty == false && !isRightToLeft(neighbor)
    }

    /// Hebrew, Arabic, Syriac, Thaana, N'Ko and their presentation forms.
    static func isRightToLeft(_ neighbor: Neighbor) -> Bool {
        guard let scalar = neighbor.text?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }
}
