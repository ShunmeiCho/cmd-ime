import QuartzCore
import SwiftUI

/// Every duration, distance and curve of the switch indicator. The bubble is
/// keyboard-initiated and appears many times a minute, so motion stays close to
/// imperceptible: opacity, a few points of travel and a three percent settle.
enum BubbleMotion {
    static let appearDuration = DesignTokens.Motion.fast
    static let dismissDuration = DesignTokens.Motion.normal
    static let reducedFadeIn = DesignTokens.Motion.fast
    static let reducedFadeOut = DesignTokens.Motion.normal

    /// Strong ease-out, used for entering and leaving alike (never ease-in).
    static let easeOutControlPoints: (Float, Float, Float, Float) = (0.23, 1, 0.32, 1)
    static var easeOutTimingFunction: CAMediaTimingFunction {
        let points = easeOutControlPoints
        return CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
    }
    static func easeOut(duration: Double) -> Animation {
        let points = easeOutControlPoints
        return .timingCurve(Double(points.0), Double(points.1), Double(points.2), Double(points.3), duration: duration)
    }

    /// Travel along the line through the corner nearest the caret.
    static let riseDistance: CGFloat = 4
    static let dismissTravel: CGFloat = 2

    /// Never from zero: the content settles from 97 percent, anchored at the caret corner.
    static let contentSettleScale: CGFloat = 0.97
    static let contentSettle = Animation.spring(response: 0.22, dampingFraction: 1.0)
    static let contentSwap = Animation.easeOut(duration: 0.10)
    /// Critically damped: the thumb has no momentum to justify a bounce.
    static let thumbSpring = Animation.spring(response: 0.30, dampingFraction: 1.0)
    static let crossfadeBlur: CGFloat = 2

    /// Measured from the end of the appear. The switcher holds longer: its thumb
    /// needs about 0.3 s to settle and the row has more to read.
    static let holdStandard = 0.75
    static let holdSwitcher = 1.10

    /// A re-trigger moves the visible bubble only when the caret went further than this.
    static let repositionThreshold: CGFloat = 24
}
