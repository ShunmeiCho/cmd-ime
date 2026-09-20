import KeyboardSwitcherCore
import SwiftUI

/// The caret badge: every slot as a bare glyph in one small capsule, with a
/// translucent thumb on the active one.
///
/// Structurally the switcher's strip with the names and the thumb's drop shadow
/// removed. Like the strip it draws the row twice, resting and emphasised, and masks
/// the emphasised copy with the thumb's shape at the thumb's position, so a glyph
/// passing under the moving thumb changes ink exactly at the thumb's edge instead of
/// crossfading. Lengths and opacities come from `BadgeMetrics`, in core, where they
/// can be tested.
struct BadgeStripView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let model: BubbleRenderModel
    /// The slot the thumb sits on; differs from the active slot only while it travels.
    let thumbIndex: Int
    /// Carousel only: cells the strip is still displaced by.
    let stripTravel: Double
    let reduceMotion: Bool

    var body: some View {
        let metrics = BadgeMetrics(model: model)
        VStack(spacing: 0) {
            strip(metrics)
            if metrics.arrangement.variant == .carousel {
                dots(metrics).padding(.top, (BadgeMetrics.Base.dotsTopGap * metrics.factor).points)
            }
        }
        .padding(metrics.padding.points)
        // Slot order is a spatial map: it is never mirrored by the target language.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Strip

    private func strip(_ metrics: BadgeMetrics) -> some View {
        let arrangement = metrics.arrangement
        let isCarousel = arrangement.variant == .carousel
        let thumbOffset = isCarousel
            ? metrics.step.points
            : (Double(min(max(thumbIndex, 0), max(model.cells.count - 1, 0))) * metrics.step).points
        let thumbCell = model.cells.indices.contains(thumbIndex) ? model.cells[thumbIndex] : nil

        return ZStack(alignment: .leading) {
            thumb(metrics, cell: thumbCell)
                .offset(x: thumbOffset)
                .id(reduceMotion ? thumbIndex : -1)
                .transition(.opacity)
            content(metrics, thumbOffset: thumbOffset, isCarousel: isCarousel)
        }
        .frame(width: metrics.windowWidth.points, height: metrics.cellHeight.points, alignment: .leading)
    }

    private func content(_ metrics: BadgeMetrics, thumbOffset: CGFloat, isCarousel: Bool) -> some View {
        ZStack(alignment: .leading) {
            cells(metrics, emphasised: false)
            cells(metrics, emphasised: true)
                .mask(alignment: .leading) {
                    thumbShape(metrics)
                        .frame(width: metrics.cellWidth.points, height: metrics.cellHeight.points)
                        .offset(x: thumbOffset)
                }
        }
        .frame(width: metrics.windowWidth.points, height: metrics.cellHeight.points, alignment: .leading)
        .mask {
            if isCarousel {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: .black, location: SwitcherStripMetrics.edgeFade),
                            .init(color: .black, location: 1 - SwitcherStripMetrics.edgeFade),
                            .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            } else {
                Rectangle()
            }
        }
    }

    private func cells(_ metrics: BadgeMetrics, emphasised: Bool) -> some View {
        let arrangement = metrics.arrangement
        let isCarousel = arrangement.variant == .carousel
        // The carousel lays out five cells around the active one; the window shows three.
        let leadingOverhang = isCarousel ? -metrics.step.points : 0
        return HStack(spacing: metrics.spacing.points) {
            ForEach(Array(arrangement.items.enumerated()), id: \.offset) { _, item in
                cell(metrics, slotIndex: item.slotIndex, emphasised: emphasised)
            }
        }
        .offset(x: leadingOverhang + CGFloat(stripTravel) * metrics.step.points)
        .id(arrangement.crossfadesContent ? model.activeIndex : -1)
        .transition(.modifier(
            active: BadgeCrossfade(opacity: 0, blur: BubbleMotion.crossfadeBlur),
            identity: BadgeCrossfade(opacity: 1, blur: 0)
        ))
        .accessibilityHidden(emphasised)
    }

    @ViewBuilder
    private func cell(_ metrics: BadgeMetrics, slotIndex: Int, emphasised: Bool) -> some View {
        if model.cells.indices.contains(slotIndex) {
            let cell = model.cells[slotIndex]
            let color = emphasised
                ? Color(bubbleHex: cell.glyphHex)
                : Color(bubbleHex: model.detailHex).opacity(restingOpacity)
            let isDouble = cell.symbol.glyph.count > 1
            let glyphSize = (isDouble ? metrics.doubleGlyphSize : metrics.glyphSize).points

            BubbleInlineSymbol(
                symbol: cell.symbol,
                font: BubbleFontResolver.display(model.typography, size: glyphSize),
                markFont: BubbleFontResolver.utility(model.typography, size: glyphSize * BubbleLayout.inlineMarkRatio),
                size: glyphSize
            )
            .foregroundStyle(color)
            .frame(width: metrics.cellWidth.points, height: metrics.cellHeight.points)
        }
    }

    /// Half-glimpsed is the point, but not when the user has asked for contrast.
    private var restingOpacity: Double {
        contrast == .increased
            ? BadgeMetrics.Ink.increasedContrastRestingOpacity
            : BadgeMetrics.Ink.restingOpacity
    }

    // MARK: - Thumb

    private func thumbShape(_ metrics: BadgeMetrics) -> RoundedRectangle {
        BubbleChrome.shape(metrics.thumbRadius)
    }

    /// A lens on the material, never a second glass element: the system material lives
    /// in an AppKit view under the hosting view and cannot follow a SwiftUI spring, and
    /// glass over glass is not what the material is for. No drop shadow either - at this
    /// size it would read as a sticker pasted onto the capsule.
    private func thumb(_ metrics: BadgeMetrics, cell: BubbleRenderModel.Cell?) -> some View {
        let fillHex = cell?.fillHex ?? model.detailHex
        // A slot-tinted thumb cannot also be translucent and still carry its glyph, so
        // only the neutral one is a lens.
        let isNeutral = fillHex == model.detailHex
        let opacity = !isNeutral ? 1
            : model.isDarkSurface ? BadgeMetrics.Ink.thumbOpacity.dark
            : BadgeMetrics.Ink.thumbOpacity.light
        let shape = thumbShape(metrics)
        return shape
            .fill(Color(bubbleHex: fillHex).opacity(opacity))
            .overlay(shape.strokeBorder(Color.white.opacity(BadgeMetrics.Ink.thumbHairlineOpacity), lineWidth: 0.5))
            .frame(width: metrics.cellWidth.points, height: metrics.cellHeight.points)
    }

    // MARK: - Dots

    private func dots(_ metrics: BadgeMetrics) -> some View {
        let factor = metrics.factor
        let size = (BadgeMetrics.Base.dotSize * factor).points
        let neutral = Color(bubbleHex: model.detailHex)
        return HStack(spacing: (BadgeMetrics.Base.dotGap * factor).points) {
            ForEach(model.cells.indices, id: \.self) { index in
                let isActive = index == model.activeIndex
                Capsule()
                    .fill(neutral.opacity(isActive ? BadgeMetrics.Ink.activeDotOpacity : BadgeMetrics.Ink.restingDotOpacity))
                    .frame(width: isActive ? (BadgeMetrics.Base.activeDotWidth * factor).points : size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BadgeCrossfade: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content.opacity(opacity).blur(radius: blur)
    }
}
