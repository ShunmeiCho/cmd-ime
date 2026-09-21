import KeyboardSwitcherCore
import SwiftUI

extension Double {
    var points: CGFloat { CGFloat(self) }
}

extension Color {
    /// Render-model colours are validated in core; a bad value draws clear, not a crash.
    init(bubbleHex hex: String) {
        self = Color(cmdIMEHex: hex) ?? .clear
    }
}

extension BubbleRenderModel {
    /// Whether the surface the content sits on is dark. With no surface the neutral
    /// text colour tells which appearance the model was resolved for.
    var isDarkSurface: Bool {
        switch substrate {
        case let .glass(isDark, _), let .liquidGlass(isDark): isDark
        case let .paper(hex), let .solid(hex): Self.isDark(hex)
        case .none: !Self.isDark(detailHex)
        }
    }

    var isPaper: Bool {
        if case .paper = substrate { return true }
        return false
    }

    var isGlassLike: Bool {
        switch substrate {
        case .glass, .liquidGlass, .solid: true
        case .paper, .none: false
        }
    }

    /// True only when a real `NSGlassEffectView` is on screen, which is the only case
    /// where the material draws its own rim and its own depth. The substrate alone is
    /// not enough: below macOS 26 a liquid theme falls through to the plain material,
    /// which supplies neither, and Reduce Transparency and Increase Contrast resolve
    /// it to `.solid`, which supplies neither either. This and the `#available` in
    /// `BubbleContainerView.setGlass` are one invariant in two places; change one and
    /// you must change the other.
    var usesSystemGlass: Bool {
        guard case .liquidGlass = substrate else { return false }
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    private static func isDark(_ hex: String) -> Bool {
        (InkLegibility.contrast(hex, "#FFFFFF") ?? 1) > (InkLegibility.contrast(hex, "#000000") ?? 1)
    }
}

enum BubbleChrome {
    static let darkGlassBase = Color(bubbleHex: "#1E1E22")
    static let lightGlassBase = Color(bubbleHex: "#F2F2F4")
    /// Stand-ins for the behind-window material where there is no window to blur
    /// (settings preview, theme miniatures). An approximation: no blur, no vibrancy.
    static let darkMaterialStandIn = Color(white: 0.12).opacity(0.78)
    static let lightMaterialStandIn = Color(white: 0.97).opacity(0.80)

    static let highlightFadeStop = 0.42
    static let darkHighlight = 0.34
    static let lightHighlight = 0.90
    static let lightInnerStrokeBoost = 0.70 / 0.16
    static let darkSeparation = 0.32
    static let lightSeparation = 0.14
    static let darkTileHairline = 0.18
    static let lightTileHairline = 0.10

    static let darkKeyShadow = 0.50
    static let darkContactShadow = 0.36
    static let lightKeyShadow = 0.30
    static let lightContactShadow = 0.20
    /// The system material renders its own depth in its drawing pass rather than as a
    /// CALayer shadow, so a drawn key shadow under it is partly a second shadow. A
    /// probe found no layer shadow but did find a private `_useReducedShadowRadius`
    /// property on the class, which means the absence of a layer shadow does not prove
    /// the absence of a shadow. This scale is a placeholder until that is settled on
    /// screen: the answer is either 0 or something near this.
    static let liquidKeyShadowScale = 0.45
    static let keyShadowRadius = 18.0
    static let keyShadowOffset = 8.0
    static let contactShadowRadius = 1.5
    static let contactShadowOffset = 1.0

    static func shape(_ radius: Double) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius.points, style: .continuous)
    }
}

/// What fills the bubble. In the live panel the glass itself is an
/// `NSVisualEffectView` under the hosting view, so only the wash is drawn here.
struct BubbleSubstrateFill: View {
    let substrate: BubbleSubstrate
    let isLive: Bool

    var body: some View {
        switch substrate {
        case let .glass(isDark, washOpacity):
            ZStack {
                if !isLive {
                    isDark ? BubbleChrome.darkMaterialStandIn : BubbleChrome.lightMaterialStandIn
                }
                (isDark ? BubbleChrome.darkGlassBase : BubbleChrome.lightGlassBase).opacity(washOpacity)
            }
        case let .liquidGlass(isDark):
            // Live: NSGlassEffectView (or the glass fallback) sits under the hosting view.
            // Previews and miniatures cannot render the system material, so they approximate it.
            if isLive {
                Color.clear
            } else {
                ZStack {
                    isDark ? BubbleChrome.darkMaterialStandIn : BubbleChrome.lightMaterialStandIn
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        case let .paper(hex), let .solid(hex):
            Color(bubbleHex: hex)
        case .none:
            Color.clear
        }
    }
}

/// Inner hairline, top-edge light and outer separation line.
struct BubbleEdges: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast
    let model: BubbleRenderModel

    var body: some View {
        let shape = BubbleChrome.shape(model.metrics.bubbleRadius)
        let hairline = 1 / max(displayScale, 1)
        let isDark = model.isDarkSurface

        ZStack {
            // The system material draws its own rim. A black hairline outside it is the
            // sticker outline, and it is the one stroke that falls outside the glass
            // frame. Every other surface still needs the separation line.
            if model.isGlassLike && !model.usesSystemGlass {
                shape.inset(by: -hairline)
                    .strokeBorder(Color.black.opacity(isDark ? BubbleChrome.darkSeparation : BubbleChrome.lightSeparation),
                                  lineWidth: hairline)
                if model.highlightStrength > 0 {
                    shape.strokeBorder(highlight(isDark: isDark), lineWidth: 1)
                        .blendMode(.plusLighter)
                }
            }
            shape.strokeBorder(innerStroke(isDark: isDark), lineWidth: contrast == .increased ? 1 : hairline)
        }
        .allowsHitTesting(false)
    }

    private func innerStroke(isDark: Bool) -> Color {
        // A white stroke vanishes on a light solid surface: under Increase Contrast the
        // border takes the text colour there, as it does on paper.
        let needsDarkBorder = contrast == .increased && !isDark
        guard model.isGlassLike, !needsDarkBorder else {
            return Color(bubbleHex: model.detailHex).opacity(model.strokeOpacity)
        }
        // The boost below exists because a white stroke disappears into a plain light
        // blur. The system material is not that, and boosting 0.10 to 0.4375 over it
        // draws a bright ring around a small capsule.
        if model.usesSystemGlass { return Color.white.opacity(model.strokeOpacity) }
        let opacity = isDark ? model.strokeOpacity : min(1, model.strokeOpacity * BubbleChrome.lightInnerStrokeBoost)
        return Color.white.opacity(opacity)
    }

    private func highlight(isDark: Bool) -> LinearGradient {
        let peak = (isDark ? BubbleChrome.darkHighlight : BubbleChrome.lightHighlight) * model.highlightStrength
        return LinearGradient(
            stops: [.init(color: .white.opacity(peak), location: 0),
                    .init(color: .clear, location: BubbleChrome.highlightFadeStop)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// The shadow is drawn here, not by the window, so previews and miniatures get the
/// same depth. It is cut out under the bubble: a translucent surface must not be
/// darkened by its own shadow.
struct BubbleOutsideShadow: View {
    let model: BubbleRenderModel

    var body: some View {
        let metrics = model.metrics
        let strength = model.shadowStrength
        let margin = metrics.shadowMargin.points
        let shape = BubbleChrome.shape(metrics.bubbleRadius)
        let isDarkGlass = model.isGlassLike && model.isDarkSurface
        let key = (isDarkGlass ? BubbleChrome.darkKeyShadow : BubbleChrome.lightKeyShadow) * strength
            * (model.usesSystemGlass ? BubbleChrome.liquidKeyShadowScale : 1)
        let contact = (isDarkGlass ? BubbleChrome.darkContactShadow : BubbleChrome.lightContactShadow) * strength

        ZStack {
            shape.fill(.black).shadow(
                color: .black.opacity(key),
                radius: (BubbleChrome.keyShadowRadius * metrics.sizeFactor).points,
                y: (BubbleChrome.keyShadowOffset * metrics.sizeFactor).points
            )
            shape.fill(.black).shadow(
                color: .black.opacity(contact),
                radius: (BubbleChrome.contactShadowRadius * metrics.sizeFactor).points,
                y: (BubbleChrome.contactShadowOffset * metrics.sizeFactor).points
            )
        }
        .padding(margin)
        .mask {
            BubbleCutout(radius: metrics.bubbleRadius.points, margin: margin)
                .fill(style: FillStyle(eoFill: true))
        }
        .padding(-margin)
        .opacity(strength > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// The whole rect plus the bubble shape; filled even-odd it leaves a bubble-shaped hole.
private struct BubbleCutout: Shape {
    let radius: CGFloat
    let margin: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect.insetBy(dx: margin, dy: margin)))
        return path
    }
}
