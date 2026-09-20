import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Lengths of the switcher strip for one render model. The arrangement (row or
/// carousel, positions, strip travel) is core's `SwitcherLayout`; this adds the
/// measured cell width it needs.
struct SwitcherStripMetrics {
    static let minCellWidth = 44.0
    static let maxCellWidth = 64.0
    static let namePadding = 8.0
    static let nameTrim = 6.0
    static let spacing = 2.0
    static let padding = 5.0
    static let thumbRadius = 11.0
    static let glyphSize = 17.0
    static let doubleGlyphSize = 13.0
    static let nameSize = 10.0
    static let textOnlyNameSize = 11.0
    /// Each size stops shrinking exactly where `switcherMinimumFactor` already stops the
    /// cell, so within the Size and Scale range nothing reaches its floor and the strip
    /// scales in one piece. Only a theme's own Text setting can push under them, and
    /// there the floor is doing its real job: keeping the name legible.
    static let minimumGlyphSize = SwitcherStripMetrics.glyphSize * BubbleMetrics.switcherMinimumFactor
    static let minimumDoubleGlyphSize = SwitcherStripMetrics.doubleGlyphSize * BubbleMetrics.switcherMinimumFactor
    static let minimumNameSize = SwitcherStripMetrics.nameSize * BubbleMetrics.switcherMinimumFactor
    static let glyphLineFactor = 1.2
    static let nameLineFactor = 1.3
    static let cellVerticalPadding = 10.0
    static let baseCellHeights = (iconAndText: 46.0, iconOnly: 36.0, textOnly: 30.0)
    static let baseTitleSize = 13.0
    static let edgeFade = 0.16
    static let dotSize = 3.0
    static let dotGap = 4.0
    static let activeDotWidth = 6.0
    static let dotsTopGap = 5.0
    static let restingOpacity = 0.72
    static let restingDotOpacity = 0.35
    static let activeDotOpacity = 0.95
    static let monochromeThumbOpacity = (dark: 0.92, light: 0.88)
    static let thumbHairlineOpacity = 0.35
    static let thumbShadow = (opacity: 0.28, radius: 3.0, y: 1.0)

    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let nameTrim: CGFloat
    let thumbShadowRadius: CGFloat
    let thumbShadowOffset: CGFloat
    let glyphSize: CGFloat
    let doubleGlyphSize: CGFloat
    let nameSize: CGFloat
    let arrangement: SwitcherArrangement

    var step: CGFloat { cellWidth + spacing }
    var windowWidth: CGFloat {
        CGFloat(arrangement.columns) * cellWidth + CGFloat(max(arrangement.columns - 1, 0)) * spacing
    }

    init(model: BubbleRenderModel) {
        let factor = model.metrics.sizeFactor
        // Text scale is folded into the title size; recover it so names and glyphs follow it.
        let textFactor = model.metrics.titleSize / Self.baseTitleSize
        let isTextOnly = model.display == .textOnly
        let name = max((isTextOnly ? Self.textOnlyNameSize : Self.nameSize) * textFactor, Self.minimumNameSize)
        let glyph = max(Self.glyphSize * textFactor, Self.minimumGlyphSize)
        let doubleGlyph = max(Self.doubleGlyphSize * textFactor, Self.minimumDoubleGlyphSize)

        let nameFont = NSFont.systemFont(ofSize: name, weight: .medium)
        let widestName = model.display == .iconOnly ? 0 : model.cells
            .map { Double(($0.name as NSString).size(withAttributes: [.font: nameFont]).width) }
            .max() ?? 0
        // The air around a name scales with everything else; an absolute padding would
        // keep its share of a shrinking cell growing.
        let width = min(max(widestName + Self.namePadding * factor, Self.minCellWidth * factor), Self.maxCellWidth * factor)

        let content: Double
        let base: Double
        switch model.display {
        case .iconAndText:
            content = glyph * Self.glyphLineFactor + name * Self.nameLineFactor
            base = Self.baseCellHeights.iconAndText
        case .iconOnly:
            content = glyph * Self.glyphLineFactor
            base = Self.baseCellHeights.iconOnly
        case .textOnly:
            content = name * Self.nameLineFactor
            base = Self.baseCellHeights.textOnly
        }

        cellWidth = width.rounded(.up).points
        cellHeight = max(base * factor, content + Self.cellVerticalPadding * factor).rounded(.up).points
        spacing = (Self.spacing * factor).points
        padding = (Self.padding * factor).points
        nameTrim = (Self.nameTrim * factor).points
        // A shadow that keeps its absolute radius grows heavier as the thumb shrinks.
        thumbShadowRadius = (Self.thumbShadow.radius * factor).points
        thumbShadowOffset = (Self.thumbShadow.y * factor).points
        glyphSize = glyph.points
        doubleGlyphSize = doubleGlyph.points
        nameSize = name.points
        arrangement = SwitcherLayout.arrangement(
            slotCount: model.cells.count,
            activeIndex: model.activeIndex,
            previousIndex: model.previousIndex,
            maxWidth: model.metrics.maxBubbleWidth,
            cellWidth: Double(cellWidth),
            spacing: Double(spacing),
            padding: Double(padding)
        )
    }
}

/// All slots side by side with a thumb behind the active one. The strip is drawn
/// twice, resting and emphasised, and the emphasised copy is masked by the thumb
/// shape at the thumb's position: a glyph under the moving thumb is always in the
/// emphasised ink, with no colour crossfade to settle.
struct SwitcherStripView: View {
    let model: BubbleRenderModel
    /// The slot the thumb sits on; differs from the active slot only while it travels.
    let thumbIndex: Int
    /// Carousel only: cells the strip is still displaced by.
    let stripTravel: Double
    let reduceMotion: Bool

    var body: some View {
        let metrics = SwitcherStripMetrics(model: model)
        VStack(spacing: 0) {
            strip(metrics)
            if metrics.arrangement.variant == .carousel {
                dots(metrics).padding(.top, (SwitcherStripMetrics.dotsTopGap * model.metrics.sizeFactor).points)
            }
        }
        .padding(metrics.padding)
        // Slot order is a spatial map: it is never mirrored by the target language.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Strip

    private func strip(_ metrics: SwitcherStripMetrics) -> some View {
        let arrangement = metrics.arrangement
        let isCarousel = arrangement.variant == .carousel
        let thumbOffset = isCarousel
            ? metrics.step
            : CGFloat(min(max(thumbIndex, 0), max(model.cells.count - 1, 0))) * metrics.step
        let thumbCell = model.cells.indices.contains(thumbIndex) ? model.cells[thumbIndex] : nil

        return ZStack(alignment: .leading) {
            thumb(metrics, cell: thumbCell)
                .offset(x: thumbOffset)
                .id(reduceMotion ? thumbIndex : -1)
                .transition(.opacity)
            content(metrics, thumbOffset: thumbOffset, isCarousel: isCarousel)
        }
        .frame(width: metrics.windowWidth, height: metrics.cellHeight, alignment: .leading)
    }

    /// Clipped to the window on its own, so the thumb's shadow is not cut with it.
    private func content(_ metrics: SwitcherStripMetrics, thumbOffset: CGFloat, isCarousel: Bool) -> some View {
        ZStack(alignment: .leading) {
            cells(metrics, emphasised: false)
            cells(metrics, emphasised: true)
                .mask(alignment: .leading) {
                    thumbShape
                        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                        .offset(x: thumbOffset)
                }
        }
        .frame(width: metrics.windowWidth, height: metrics.cellHeight, alignment: .leading)
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

    private func cells(_ metrics: SwitcherStripMetrics, emphasised: Bool) -> some View {
        let arrangement = metrics.arrangement
        let isCarousel = arrangement.variant == .carousel
        // The carousel lays out five cells around the active one; the window shows three.
        let leadingOverhang = isCarousel ? -metrics.step : 0
        return HStack(spacing: metrics.spacing) {
            ForEach(Array(arrangement.items.enumerated()), id: \.offset) { _, item in
                cell(metrics, slotIndex: item.slotIndex, emphasised: emphasised)
            }
        }
        .offset(x: leadingOverhang + CGFloat(stripTravel) * metrics.step)
        .id(arrangement.crossfadesContent ? model.activeIndex : -1)
        .transition(.modifier(
            active: CrossfadeBlur(opacity: 0, blur: BubbleMotion.crossfadeBlur),
            identity: CrossfadeBlur(opacity: 1, blur: 0)
        ))
        .accessibilityHidden(emphasised)
    }

    @ViewBuilder
    private func cell(_ metrics: SwitcherStripMetrics, slotIndex: Int, emphasised: Bool) -> some View {
        if model.cells.indices.contains(slotIndex) {
            let cell = model.cells[slotIndex]
            let color = emphasised
                ? Color(bubbleHex: cell.glyphHex)
                : Color(bubbleHex: model.detailHex).opacity(SwitcherStripMetrics.restingOpacity)
            let isDouble = cell.symbol.glyph.count > 1
            let glyphSize = isDouble ? metrics.doubleGlyphSize : metrics.glyphSize

            VStack(spacing: 0) {
                if model.display != .textOnly {
                    BubbleInlineSymbol(
                        symbol: cell.symbol,
                        font: BubbleFontResolver.display(model.typography, size: glyphSize),
                        markFont: BubbleFontResolver.utility(model.typography, size: glyphSize * BubbleLayout.inlineMarkRatio),
                        size: glyphSize
                    )
                    .frame(height: glyphSize * SwitcherStripMetrics.glyphLineFactor)
                }
                if model.display != .iconOnly {
                    Text(cell.name)
                        .font(BubbleFontResolver.utility(model.typography, size: metrics.nameSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: metrics.cellWidth - metrics.nameTrim,
                               height: metrics.nameSize * SwitcherStripMetrics.nameLineFactor)
                }
            }
            .foregroundStyle(color)
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        }
    }

    // MARK: - Thumb

    private var thumbShape: RoundedRectangle {
        BubbleChrome.shape(SwitcherStripMetrics.thumbRadius * model.metrics.sizeFactor)
    }

    private func thumb(_ metrics: SwitcherStripMetrics, cell: BubbleRenderModel.Cell?) -> some View {
        let fillHex = cell?.fillHex ?? model.detailHex
        // The monochrome thumb is the neutral colour itself and stays slightly translucent.
        let isNeutral = fillHex == model.detailHex
        let opacity = !isNeutral ? 1
            : model.isDarkSurface ? SwitcherStripMetrics.monochromeThumbOpacity.dark
            : SwitcherStripMetrics.monochromeThumbOpacity.light
        return thumbShape
            .fill(Color(bubbleHex: fillHex).opacity(opacity))
            .overlay(thumbShape.strokeBorder(Color.white.opacity(SwitcherStripMetrics.thumbHairlineOpacity), lineWidth: 0.5))
            .shadow(
                color: .black.opacity(SwitcherStripMetrics.thumbShadow.opacity),
                radius: metrics.thumbShadowRadius,
                y: metrics.thumbShadowOffset
            )
            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
    }

    // MARK: - Dots

    /// The carousel shows three slots; the dots are the overview of all of them.
    private func dots(_ metrics: SwitcherStripMetrics) -> some View {
        let factor = model.metrics.sizeFactor
        let size = (SwitcherStripMetrics.dotSize * factor).points
        let neutral = Color(bubbleHex: model.detailHex)
        return HStack(spacing: (SwitcherStripMetrics.dotGap * factor).points) {
            ForEach(model.cells.indices, id: \.self) { index in
                let isActive = index == model.activeIndex
                Capsule()
                    .fill(neutral.opacity(isActive ? SwitcherStripMetrics.activeDotOpacity : SwitcherStripMetrics.restingDotOpacity))
                    .frame(width: isActive ? (SwitcherStripMetrics.activeDotWidth * factor).points : size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CrossfadeBlur: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content.opacity(opacity).blur(radius: blur)
    }
}
