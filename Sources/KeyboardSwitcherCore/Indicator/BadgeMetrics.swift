import Foundation

/// Every length of the caret badge, in points, already multiplied by the Size and
/// Scale settings.
///
/// The badge is the switcher's row reduced to glyph-sized cells: it draws no slot
/// names, so nothing budgets width for one. Its cell is measured from the glyph it
/// carries, the way `BubbleTile` sizes its glyph from the tile, and every length
/// here scales together. The badge has no absolute floor in the view; its single
/// floor is `BubbleMetrics.badgeMinimumFactor`, stated once where a test can pin it.
public struct BadgeMetrics: Equatable, Sendable {
    public enum Base {
        public static let cellHeight = 18.0
        public static let padding = 3.0
        public static let spacing = 2.0
        public static let glyphSize = 13.0
        public static let doubleGlyphSize = 10.0
        public static let cellHorizontalPadding = 3.5
        public static let cellVerticalPadding = 2.0
        public static let glyphLineFactor = 1.2
        /// Widths, in multiples of `glyphSize`. The widest single glyph is CJK at
        /// 0.99 em; a two-character glyph is an ISO code or, through a user override,
        /// two CJK characters, which measure 1.53 em of the single-glyph size.
        public static let singleGlyphUnits = 1.0
        public static let doubleGlyphUnits = 1.55
        /// Must equal the view's `BubbleLayout.inlineMarkRatio`: the mark is drawn at
        /// this fraction of its glyph's size, and the cell has to budget for it.
        public static let markRatio = 0.62
        /// A safety net for a duplicated theme whose Text setting is dragged down as
        /// well; dead at the default text scale, where the floor factor already keeps
        /// the glyph at 9.10 pt. The cell is measured from the glyph after this clamp,
        /// so the frame follows the text rather than shrinking past it.
        public static let minimumGlyphSize = 9.0
        public static let minimumDoubleGlyphSize = 7.0
        public static let dotSize = 2.5
        public static let dotGap = 3.0
        public static let activeDotWidth = 5.0
        public static let dotsTopGap = 3.0
    }

    /// Translucency is the badge's material, not a fallback for one colour style, so
    /// these apply unconditionally rather than only to a neutral thumb.
    public enum Ink {
        /// The lowest opacity at which an inactive glyph still reaches the WCAG text
        /// minimum over the light glass base: 7.16:1 dark, 4.55:1 light.
        public static let restingOpacity = 0.62
        /// Under Increase Contrast the resting slot stops being half-glimpsed.
        public static let increasedContrastRestingOpacity = 0.85
        public static let thumbOpacity = (dark: 0.72, light: 0.66)
        /// Specular light along the thumb's edge, softer than the switcher's 0.35.
        public static let thumbHairlineOpacity = 0.22
        public static let restingDotOpacity = 0.30
        public static let activeDotOpacity = 0.90
    }

    public let factor: Double
    public let glyphSize: Double
    public let doubleGlyphSize: Double
    public let cellWidth: Double
    public let cellHeight: Double
    public let spacing: Double
    public let padding: Double
    public let thumbRadius: Double
    public let arrangement: SwitcherArrangement

    public var step: Double { cellWidth + spacing }

    public var windowWidth: Double {
        Double(arrangement.columns) * cellWidth + Double(max(arrangement.columns - 1, 0)) * spacing
    }

    public var bubbleWidth: Double { windowWidth + 2 * padding }

    public var bubbleHeight: Double { cellHeight + 2 * padding }

    public init(model: BubbleRenderModel) {
        let factor = model.metrics.sizeFactor
        // Text scale is folded into the title size; recover it so the glyph follows it.
        let textFactor = model.metrics.titleSize / BubbleMetrics.Base.titleSize

        self.factor = factor
        glyphSize = Self.glyphSize(textFactor: textFactor, isDouble: false)
        doubleGlyphSize = Self.glyphSize(textFactor: textFactor, isDouble: true)
        cellHeight = Self.cellHeight(factor: factor, textFactor: textFactor)
        // Only the width is rounded: it comes from measured text. Rounding the height
        // too would leave the bubble radius short of half the height and the capsule open.
        cellWidth = max(cellHeight, glyphSize * Self.glyphUnits(for: model.cells)
            + 2 * Base.cellHorizontalPadding * factor).rounded(.up)
        spacing = Base.spacing * factor
        padding = Base.padding * factor
        thumbRadius = cellHeight / 2
        arrangement = SwitcherLayout.arrangement(
            slotCount: model.cells.count,
            activeIndex: model.activeIndex,
            previousIndex: model.previousIndex,
            maxWidth: model.metrics.maxBubbleWidth,
            cellWidth: cellWidth,
            spacing: spacing,
            padding: padding
        )
    }

    public static func glyphSize(textFactor: Double, isDouble: Bool) -> Double {
        isDouble
            ? max(Base.doubleGlyphSize * textFactor, Base.minimumDoubleGlyphSize)
            : max(Base.glyphSize * textFactor, Base.minimumGlyphSize)
    }

    /// The cell never shrinks past the glyph it carries, so a larger Text setting
    /// grows the badge instead of clipping inside a fixed height.
    public static func cellHeight(factor: Double, textFactor: Double) -> Double {
        max(
            Base.cellHeight * factor,
            glyphSize(textFactor: textFactor, isDouble: false) * Base.glyphLineFactor
                + Base.cellVerticalPadding * factor
        )
    }

    /// `BubbleMetrics.baseHeight` for the badge; the measured bubble is the same height.
    public static func bubbleHeight(factor: Double, textFactor: Double) -> Double {
        cellHeight(factor: factor, textFactor: textFactor) + 2 * Base.padding * factor
    }

    /// Cells share one width, so the widest content decides it. A mark is part of that
    /// content: `BubbleInlineSymbol` is fixed-size and would otherwise draw over its
    /// neighbour rather than truncate.
    public static func glyphUnits(for cells: [BubbleRenderModel.Cell]) -> Double {
        cells.map { cell in
            let isDouble = cell.symbol.glyph.count > 1
            let glyph = isDouble ? Base.doubleGlyphUnits : Base.singleGlyphUnits
            guard cell.symbol.mark != nil else { return glyph }
            let markScale = isDouble ? Base.doubleGlyphSize / Base.glyphSize : 1
            return glyph + Base.markRatio * markScale
        }
        .max() ?? Base.singleGlyphUnits
    }
}
