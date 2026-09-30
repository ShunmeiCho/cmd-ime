import Foundation

/// The adaptive bubble's growth from the Mark into the Badge row, as pure functions of
/// the time since it started. The panel is sized for the row from the first frame, so
/// only the pill inside it moves: its width and height, the row sliding out from under
/// the Mark's glyph, and the other glyphs arriving one after another. One clock drives
/// the glass underneath and the SwiftUI edges over it, so the two never drift apart.
public enum AdaptiveExpansion {
    /// Critically damped, with the same response as the Badge thumb's spring: the row
    /// and the thumb inside it move as one gesture, and nothing has momentum that would
    /// justify a bounce.
    public static let springResponse = 0.24
    /// The spring is treated as settled once less than this fraction of the growth is left:
    /// on a row about 100 points wider than the Mark that is under half a point.
    public static let settleThreshold = 0.004
    /// Between one glyph and the next one further from the Mark.
    public static let staggerDelay = 0.03
    /// Each glyph fades and grows in over this long, with a strong ease-out.
    public static let revealDuration = 0.18
    /// Never from nothing: an arriving glyph starts at this scale.
    public static let revealStartScale = 0.92

    public struct Size: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// Spring progress from 0 to 1, `time` seconds after the growth began.
    public static func progress(at time: Double, response: Double = springResponse) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        return 1 - (1 + omega * time) * exp(-omega * time)
    }

    /// When the spring counts as settled, from the same closed form.
    public static func settleTime(response: Double = springResponse) -> Double {
        // Solve (1 + x) e^-x = threshold for x = omega * t by bisection; it is monotonic.
        var low = 0.0, high = 50.0
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if (1 + mid) * exp(-mid) > settleThreshold { low = mid } else { high = mid }
        }
        return high * response / (2 * Double.pi)
    }

    /// How far the glyph `distance` cells from the Mark's has arrived, 0 to 1. The Mark's
    /// own glyph (distance 0) is already there: it is the one the user was looking at.
    public static func reveal(at time: Double, distance: Int) -> Double {
        guard distance > 0 else { return 1 }
        let start = Double(distance - 1) * staggerDelay
        let linear = min(max((time - start) / revealDuration, 0), 1)
        let remaining = 1 - linear
        return 1 - remaining * remaining * remaining
    }

    /// The scale that goes with a reveal value.
    public static func revealScale(_ reveal: Double) -> Double {
        revealStartScale + (1 - revealStartScale) * reveal
    }

    /// Done when the spring has settled and the furthest glyph has arrived.
    public static func isFinished(at time: Double, maxDistance: Int) -> Bool {
        let lastReveal = Double(max(maxDistance - 1, 0)) * staggerDelay + revealDuration
        return time >= max(settleTime(), maxDistance > 0 ? lastReveal : 0)
    }

    /// The area the panel keeps for the bubble: room for either layout, so growing never
    /// resizes or moves the panel.
    public static func reservedSize(compact: Size, expanded: Size) -> Size {
        Size(width: max(compact.width, expanded.width), height: max(compact.height, expanded.height))
    }

    /// The pill at `progress`, between the Mark's size and the row's.
    public static func pillSize(compact: Size, expanded: Size, progress: Double) -> Size {
        Size(
            width: compact.width + (expanded.width - compact.width) * progress,
            height: compact.height + (expanded.height - compact.height) * progress
        )
    }

    /// The pill's bottom-left corner inside the reserved area, y growing upward. It keeps
    /// the leading edge and the edge nearest the caret: above the caret that is the bottom.
    public static func pillOrigin(pill: Size, reserved: Size, anchor: BubblePlacement.Anchor) -> (x: Double, y: Double) {
        (0, anchor == .bottomLeading ? 0 : reserved.height - pill.height)
    }

    /// How far the row is shifted so the Mark's glyph starts where the Mark drew it and
    /// slides into its own cell as the pill grows. `markGlyphCenter` and `cellCenter` are
    /// both measured from the pill's leading edge.
    public static func rowOffset(progress: Double, markGlyphCenter: Double, cellCenter: Double) -> Double {
        (1 - progress) * (markGlyphCenter - cellCenter)
    }

    /// The centre of `slotIndex`'s cell in a Badge row laid out in a plain row, from the
    /// pill's leading edge; nil for a carousel, whose window scrolls rather than grows.
    public static func badgeCellCenter(_ metrics: BadgeMetrics, slotIndex: Int) -> Double? {
        guard metrics.arrangement.variant != .carousel,
              let position = metrics.arrangement.items.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return nil
        }
        return metrics.padding + Double(position) * metrics.step + metrics.cellWidth / 2
    }
}
