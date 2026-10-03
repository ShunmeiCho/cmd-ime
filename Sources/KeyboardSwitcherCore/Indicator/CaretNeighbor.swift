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

    /// The caret from what the neighbors say, or nil when it cannot be told (review A2):
    /// - right-to-left text, where the logical edge is on the other visual side;
    /// - two neighbors on different lines (a soft wrap), where the caret could be at either.
    public static func caret(before: Neighbor?, after: Neighbor?) -> Rect? {
        guard ![before, after].contains(where: { $0.map(isRightToLeft) ?? false }) else { return nil }
        switch (before, after) {
        case let (before?, after?):
            let lineHeight = min(before.rect.height, after.rect.height)
            guard abs(before.rect.y - after.rect.y) < lineHeight / 2 else { return nil }
            return caret(fromCharacter: before.rect, side: .before)
        case let (before?, nil): return caret(fromCharacter: before.rect, side: .before)
        case let (nil, after?): return caret(fromCharacter: after.rect, side: .after)
        case (nil, nil): return nil
        }
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
