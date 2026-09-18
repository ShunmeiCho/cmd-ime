import Foundation

/// Where the bubble goes, in AppKit screen coordinates (y grows upward). The origin
/// is always the bubble's bottom-leading corner; the anchor names the corner that
/// stays nearest the caret, which is the corner motion grows from.
public struct BubblePlacement: Equatable, Sendable {
    public enum Anchor: Sendable {
        /// The bubble sits above the caret.
        case bottomLeading
        /// The bubble was flipped below the caret.
        case topLeading
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// The bubble appears this far right of the caret's centre and above its top.
    public static let caretOffsetX = 10.0
    public static let caretOffsetY = 18.0
    public static let screenMargin = 8.0

    public let originX: Double
    public let originY: Double
    public let anchor: Anchor

    /// Without a caret the pointer stands in for it. Only the bubble is kept inside
    /// the visible frame; its shadow margin may hang over a screen edge.
    public static func resolve(
        caret: Rect?,
        pointerX: Double,
        pointerY: Double,
        bubbleWidth: Double,
        bubbleHeight: Double,
        visible: Rect
    ) -> BubblePlacement {
        let target = caret ?? Rect(x: pointerX, y: pointerY, width: 0, height: 0)
        let preferredX = target.x + target.width / 2 + caretOffsetX
        let above = target.maxY + caretOffsetY
        let fitsAbove = above + bubbleHeight <= visible.maxY - screenMargin
        let preferredY = fitsAbove ? above : target.y - caretOffsetY - bubbleHeight

        return BubblePlacement(
            originX: clamped(preferredX, low: visible.x + screenMargin, high: visible.maxX - screenMargin - bubbleWidth),
            originY: clamped(preferredY, low: visible.y + screenMargin, high: visible.maxY - screenMargin - bubbleHeight),
            anchor: fitsAbove ? .bottomLeading : .topLeading
        )
    }

    /// A re-trigger while the bubble is showing: the new size grows from the anchor
    /// corner of the old frame, then is kept inside the visible frame like a fresh one.
    public static func resized(
        from old: Rect,
        anchor: Anchor,
        width: Double,
        height: Double,
        visible: Rect
    ) -> Rect {
        let y = anchor == .bottomLeading ? old.y : old.maxY - height
        return Rect(
            x: clamped(old.x, low: visible.x + screenMargin, high: visible.maxX - screenMargin - width),
            y: clamped(y, low: visible.y + screenMargin, high: visible.maxY - screenMargin - height),
            width: width,
            height: height
        )
    }

    /// The low bound wins when the bubble is larger than the space between the margins.
    private static func clamped(_ value: Double, low: Double, high: Double) -> Double {
        max(min(value, high), low)
    }
}
