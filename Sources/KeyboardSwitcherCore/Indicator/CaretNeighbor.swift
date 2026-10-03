import Foundation

/// Where the caret is when an app gives no rect for the caret itself but does for the character next to it
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

    /// The character before the caret first (the usual case while typing), then the one after it.
    public static func candidates(caretLocation: Int) -> [Candidate] {
        (caretLocation > 0 ? [Candidate(location: caretLocation - 1, side: .before)] : [])
            + [Candidate(location: caretLocation, side: .after)]
    }

    /// A zero-width caret rect at the character's trailing or leading edge, as tall as the character.
    public static func caret(fromCharacter rect: Rect, side: Side) -> Rect {
        Rect(x: side == .before ? rect.x + rect.width : rect.x, y: rect.y, width: 0, height: rect.height)
    }
}
