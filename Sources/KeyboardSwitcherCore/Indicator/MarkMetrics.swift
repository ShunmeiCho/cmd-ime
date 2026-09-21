import Foundation

/// Every length of the caret mark, in points, already multiplied by the Size setting.
///
/// The mark answers one question - which input source you just switched to - and so
/// it draws one symbol inside one surface, the way the system's own caret badge does.
/// Where the Badge keeps every slot side by side with a thumb on the active one, this
/// keeps only the answer.
///
/// Nothing here has an absolute floor except a legibility guard on the glyph: the one
/// floor is a factor, `BubbleMetrics.markMinimumFactor`, so every length shrinks in
/// step.
public struct MarkMetrics: Equatable, Sendable {
    public enum Base {
        /// Body typography: 13 points on a 16 point line, which is what the system
        /// sets text of this size on. The capsule is that line box plus its air.
        public static let glyphSize = 13.0
        public static let lineBox = 16.0
        public static let verticalPadding = 4.0
        public static let horizontalPadding = 7.5
        /// A badge is never narrower than this, so a narrow glyph still reads as a
        /// mark rather than as a sliver.
        public static let minimumWidth = 28.0
        /// The disambiguating mark, in multiples of the glyph size: 10 points beside a
        /// 13 point glyph, set on the baseline rather than raised. Raised and much
        /// smaller, it read as a footnote on a miniature button.
        public static let markRatio = 10.0 / 13.0
        public static let markGap = 2.0
        /// Widths, in multiples of the glyph size. The widest single glyph is CJK at
        /// 0.99 em; a two-character glyph is an ISO code or, through a user override,
        /// two CJK characters, which measure 1.53 em of the single-glyph size.
        public static let singleGlyphUnits = 1.0
        public static let doubleGlyphUnits = 1.55
        /// A safety net for a duplicated theme whose Text setting is dragged down as
        /// well; dead at the default text scale, where the floor factor already keeps
        /// the glyph at 9.10 points. The capsule is measured from the glyph after this
        /// clamp, so the surface follows the text rather than shrinking past it.
        public static let minimumGlyphSize = 9.0
    }

    public let factor: Double
    public let glyphSize: Double
    public let markSize: Double
    public let bubbleWidth: Double
    public let bubbleHeight: Double

    public init(model: BubbleRenderModel) {
        let factor = model.metrics.sizeFactor
        // Text scale is folded into the title size; recover it so the glyph follows it.
        let textFactor = model.metrics.titleSize / BubbleMetrics.Base.titleSize

        self.factor = factor
        glyphSize = Self.glyphSize(textFactor: textFactor)
        markSize = glyphSize * Base.markRatio
        bubbleHeight = Self.bubbleHeight(factor: factor, textFactor: textFactor)
        bubbleWidth = max(
            Base.minimumWidth * factor,
            glyphSize * Self.contentUnits(for: model.symbol) + 2 * Base.horizontalPadding * factor
        )
    }

    public static func glyphSize(textFactor: Double) -> Double {
        max(Base.glyphSize * textFactor, Base.minimumGlyphSize)
    }

    /// `BubbleMetrics.baseHeight` for the badge, and the height the panel measures. The
    /// line box follows whichever of Size or Text is larger, so a bigger Text setting
    /// grows the capsule instead of clipping inside it.
    public static func bubbleHeight(factor: Double, textFactor: Double) -> Double {
        let lineBox = max(Base.lineBox * factor, Base.lineBox * textFactor)
        return lineBox + 2 * Base.verticalPadding * factor
    }

    /// What the capsule has to hold, in multiples of the glyph size. A mark is part of
    /// that: it is drawn beside the glyph at a fixed size and is never truncated.
    public static func contentUnits(for symbol: SlotSymbol) -> Double {
        let glyph = symbol.glyph.count > 1 ? Base.doubleGlyphUnits : Base.singleGlyphUnits
        guard symbol.mark != nil else { return glyph }
        return glyph + Base.markRatio + Base.markGap / Base.glyphSize
    }
}
