import KeyboardSwitcherCore
import SwiftUI

/// Layout ratios shared by every archetype. Lengths that depend on Size, Scale or
/// the theme come from `BubbleMetrics`; these are the proportions inside a part.
enum BubbleLayout {
    static let singleGlyphTileRatio = 0.56
    static let doubleGlyphTileRatio = 0.42
    static let glyphMinimumScale = 0.6
    static let titleMinimumScale = 0.85
    static let markTileRatio = 0.30
    static let markOpacity = 0.9
    static let markInset = 2.0
    static let barWidth = 3.0
    static let barRadius = 1.5
    static let ruleWidth = 12.0
    static let ruleHeight = 1.5
    static let ruleGap = 4.0
    static let stackedTitleTracking = -0.3
    /// Latin, Greek and Cyrillic end here; tighter tracking suits only those scripts.
    static let trackedScriptsUpperBound: UInt32 = 0x0530
    static let inlineMarkRatio = 0.62
    static let inlineMarkLift = 0.30
}

/// The opaque rounded square that carries the slot's symbol.
struct BubbleTile: View {
    @Environment(\.displayScale) private var displayScale
    let model: BubbleRenderModel

    var body: some View {
        let metrics = model.metrics
        let side = metrics.tileSide.points
        let shape = BubbleChrome.shape(metrics.tileRadius)
        let isDouble = model.symbol.glyph.count > 1
        let glyphSize = side * (isDouble ? BubbleLayout.doubleGlyphTileRatio : BubbleLayout.singleGlyphTileRatio)
        let glyphColor = Color(bubbleHex: model.glyphHex)

        Text(model.symbol.glyph)
            .font(BubbleFontResolver.display(model.typography, size: glyphSize,
                                             weight: model.typography.displayWeight == .heavy ? .heavy : .bold))
            .foregroundStyle(glyphColor)
            .lineLimit(1)
            .minimumScaleFactor(BubbleLayout.glyphMinimumScale)
            .frame(width: side, height: side)
            .background(shape.fill(Color(bubbleHex: model.tileFillHex ?? model.titleHex)))
            .overlay {
                if !model.isPaper {
                    shape.strokeBorder(
                        model.isDarkSurface ? Color.white.opacity(BubbleChrome.darkTileHairline)
                            : Color.black.opacity(BubbleChrome.lightTileHairline),
                        lineWidth: 1 / max(displayScale, 1)
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if let mark = model.symbol.mark {
                    Text(mark)
                        .font(BubbleFontResolver.utility(model.typography, size: side * BubbleLayout.markTileRatio))
                        .foregroundStyle(glyphColor.opacity(BubbleLayout.markOpacity))
                        .lineLimit(1)
                        .fixedSize()
                        .padding((BubbleLayout.markInset * metrics.sizeFactor).points)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A symbol set inline with text: the glyph, then its mark raised and smaller.
struct BubbleInlineSymbol: View {
    let symbol: SlotSymbol
    let font: Font
    let markFont: Font
    let size: CGFloat

    var body: some View {
        (Text(symbol.glyph).font(font)
            + Text(symbol.mark ?? "").font(markFont).baselineOffset(size * BubbleLayout.inlineMarkLift))
            .lineLimit(1)
            .fixedSize()
    }
}

struct BubbleTitle: View {
    let model: BubbleRenderModel
    var tracking: CGFloat = 0

    var body: some View {
        Text(model.title)
            .font(BubbleFontResolver.display(model.typography, size: model.metrics.titleSize.points))
            .tracking(tracking)
            .foregroundStyle(Color(bubbleHex: model.titleHex))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(BubbleLayout.titleMinimumScale)
            .frame(height: model.metrics.titleLineHeight.points)
    }
}

/// One line, never scaled; input source names differ at the end, so the middle goes first.
struct BubbleDetail: View {
    let model: BubbleRenderModel

    var body: some View {
        Text(model.detail)
            .font(BubbleFontResolver.utility(model.typography, size: model.metrics.detailSize.points))
            .foregroundStyle(Color(bubbleHex: model.detailHex).opacity(model.detailOpacity))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(height: model.metrics.detailLineHeight.points)
    }
}

// MARK: - Archetypes

struct TileTwoLineBubble: View {
    let model: BubbleRenderModel

    var body: some View {
        let metrics = model.metrics
        switch model.display {
        case .iconAndText:
            HStack(spacing: metrics.gap.points) {
                BubbleTile(model: model)
                VStack(alignment: .leading, spacing: 0) {
                    BubbleTitle(model: model)
                    BubbleDetail(model: model)
                }
                .frame(minWidth: metrics.textMinWidth.points, maxWidth: metrics.textMaxWidth.points, alignment: .leading)
            }
            .padding(.leading, metrics.inset.points)
            .padding(.vertical, metrics.inset.points)
            .padding(.trailing, metrics.trailingPadding.points)
        case .iconOnly:
            BubbleTile(model: model).padding(metrics.inset.points)
        case .textOnly:
            BubbleTitle(model: model)
                .frame(maxWidth: metrics.textMaxWidth.points)
                .padding(.horizontal, metrics.trailingPadding.points)
                .frame(minHeight: metrics.baseHeight.points)
        }
    }
}

struct LineWithBarBubble: View {
    let model: BubbleRenderModel

    var body: some View {
        let metrics = model.metrics
        let factor = metrics.sizeFactor
        let titleSize = metrics.titleSize.points
        HStack(spacing: metrics.gap.points) {
            RoundedRectangle(cornerRadius: (BubbleLayout.barRadius * factor).points, style: .continuous)
                .fill(Color(bubbleHex: model.barHex ?? model.titleHex))
                .frame(width: (BubbleLayout.barWidth * factor).points, height: metrics.titleLineHeight.points)
            if model.display != .textOnly {
                BubbleInlineSymbol(
                    symbol: model.symbol,
                    font: BubbleFontResolver.display(model.typography, size: titleSize),
                    markFont: BubbleFontResolver.utility(model.typography, size: titleSize * BubbleLayout.inlineMarkRatio),
                    size: titleSize
                )
                .foregroundStyle(Color(bubbleHex: model.glyphHex))
            }
            if model.display != .iconOnly {
                BubbleTitle(model: model).frame(maxWidth: metrics.textMaxWidth.points, alignment: .leading)
            }
        }
        .padding(.leading, metrics.inset.points)
        .padding(.trailing, metrics.trailingPadding.points)
        .frame(minHeight: metrics.baseHeight.points)
    }
}

struct StackedTextBubble: View {
    let model: BubbleRenderModel

    var body: some View {
        let metrics = model.metrics
        let factor = metrics.sizeFactor
        let isTracked = model.title.unicodeScalars.allSatisfy { $0.value < BubbleLayout.trackedScriptsUpperBound }
        VStack(alignment: .leading, spacing: 0) {
            BubbleTitle(model: model, tracking: isTracked ? (BubbleLayout.stackedTitleTracking * factor).points : 0)
            Rectangle()
                .fill(Color(bubbleHex: model.barHex ?? model.titleHex))
                .frame(width: (BubbleLayout.ruleWidth * factor).points, height: (BubbleLayout.ruleHeight * factor).points)
                .frame(height: (BubbleLayout.ruleGap * factor).points)
            BubbleDetail(model: model)
        }
        .frame(minWidth: metrics.textMinWidth.points, maxWidth: metrics.textMaxWidth.points, alignment: .leading)
        .padding(.horizontal, metrics.trailingPadding.points)
        .frame(minHeight: metrics.baseHeight.points)
    }
}
