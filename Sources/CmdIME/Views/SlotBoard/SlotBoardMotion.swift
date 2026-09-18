import SwiftUI

/// Drive from zero to one with `Motion.rejectShake`; gate the effect at the call site for Reduce Motion.
struct Shake: GeometryEffect {
    var progress: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let p = min(max(progress, 0), 1)
        let offset = sin(3 * .pi * p) * amplitude * (1 - p)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// Owns the card's tint outline while pulsing: do not stack with another tint stroke or glow.
/// Drive zero to one using `Motion.seatPulse`; both endpoints are the resting outline.
struct SeatPulse: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    var tint: Color
    var reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let intensity = max(0, sin(.pi * p))
        content.overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.22 + 0.52 * Double(intensity)), lineWidth: 1)
                .shadow(color: tint.opacity(reduceMotion ? 0 : 0.26 * Double(intensity)),
                        radius: reduceMotion ? 0 : 14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// macOS 13 progress observer. Animate zero to one with `.linear(duration: Motion.slow)`.
/// Completion is deferred out of the render update; callers must guard stale runs and be idempotent.
struct MotionCompletion: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    var completion: () -> Void

    init(progress: CGFloat, completion: @escaping () -> Void) {
        self.progress = progress
        self.completion = completion
    }

    var animatableData: CGFloat {
        get { progress }
        set {
            progress = newValue
            // SwiftUI interpolates value copies; the stored value may already
            // be the destination. Observe arrival, not a previous-frame crossing.
            if newValue >= 1 {
                let callback = completion
                DispatchQueue.main.async { callback() }
            }
        }
    }

    func body(content: Content) -> some View { content }
}

enum SlotBoardMotion {
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        // Reduced-motion insertion uses the card's local appeared-opacity fade;
        // removal and sibling layout changes remain instantaneous.
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
            removal: .scale(scale: 0.98).combined(with: .opacity)
                .animation(DesignTokens.Motion.quickFade)
        )
    }

    static func noticeTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(DesignTokens.Motion.quickFade)
        }
        // The parent's expandCollapse transaction animates the notice's layout height.
        return .opacity
    }
}
