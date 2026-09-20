import QuartzCore
import SwiftUI

/// Every duration, distance and curve of the switch indicator. The bubble is
/// keyboard-initiated and appears many times a minute, so motion stays close to
/// imperceptible: opacity, a few points of travel and a three percent settle.
enum BubbleMotion {
    /// Long enough to be a transition rather than a step. At 0.14 s the appear had
    /// about three frames of visible change and the old curve spent 46 percent of the
    /// motion in the first one, so the bubble arrived already half opaque: a pop, not
    /// a fade.
    static let appearDuration = 0.22
    static let dismissDuration = DesignTokens.Motion.normal
    static let reducedFadeIn = DesignTokens.Motion.fast
    static let reducedFadeOut = DesignTokens.Motion.normal

    /// Decelerate, for arriving: it leaves at full speed and eases into rest, so the
    /// motion is spread across the whole duration instead of front-loaded.
    static let appearControlPoints: (Float, Float, Float, Float) = (0, 0, 0.2, 1)
    static var appearTimingFunction: CAMediaTimingFunction {
        let points = appearControlPoints
        return CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
    }

    /// Strong ease-out, for leaving (never ease-in).
    static let easeOutControlPoints: (Float, Float, Float, Float) = (0.23, 1, 0.32, 1)
    static var easeOutTimingFunction: CAMediaTimingFunction {
        let points = easeOutControlPoints
        return CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
    }
    static func easeOut(duration: Double) -> Animation {
        let points = easeOutControlPoints
        return .timingCurve(Double(points.0), Double(points.1), Double(points.2), Double(points.3), duration: duration)
    }

    /// Travel on the way out only, along the line through the corner nearest the caret.
    /// The appear has none: a window origin lands on whole points, so the four points
    /// it used to rise had five reachable positions, and most of the motion was spent
    /// standing still.
    static let dismissTravel: CGFloat = 2

    /// Never from zero: the content settles from 97 percent, anchored at the caret corner.
    static let contentSettleScale: CGFloat = 0.97
    /// One clock for the whole appearance. This used to be a spring that needed about
    /// 0.23 s to reach 99 percent against a 0.14 s window animation, so the bubble
    /// stopped hard and then drifted for another quarter second.
    static let contentSettle = Animation.timingCurve(
        Double(appearControlPoints.0), Double(appearControlPoints.1),
        Double(appearControlPoints.2), Double(appearControlPoints.3),
        duration: appearDuration
    )
    static let contentSwap = Animation.easeOut(duration: 0.10)
    /// Critically damped: the thumb has no momentum to justify a bounce.
    static let thumbSpring = Animation.spring(response: 0.30, dampingFraction: 1.0)
    /// The badge's thumb crosses about 22 points between neighbours where the
    /// switcher's crosses about 48; the switcher's response reads as drag over that
    /// shorter distance.
    static let badgeThumbSpring = Animation.spring(response: 0.24, dampingFraction: 1.0)
    static let crossfadeBlur: CGFloat = 2

    /// Measured from the end of the appear. The switcher holds longer: its thumb
    /// needs about 0.3 s to settle and the row has more to read.
    static let holdStandard = 0.75
    static let holdSwitcher = 1.10
    /// Between the two: the badge's thumb still has to arrive, but there are no slot
    /// names to read.
    static let holdBadge = 0.85

    /// A re-trigger moves the visible bubble only when the caret went further than this.
    static let repositionThreshold: CGFloat = 24
    /// Shorter than the appear: the bubble is already on screen and being read, so the
    /// move has to be over before the eye follows it rather than leading the eye.
    static let repositionDuration = 0.18
}
