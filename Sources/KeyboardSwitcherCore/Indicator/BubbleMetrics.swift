import Foundation

/// How the stored Display setting composes with a theme's layout. The stored value
/// is never rewritten; an unsupported one is coerced for rendering only.
public enum IndicatorDisplayComposition {
    public static func supported(_ archetype: BubbleArchetype) -> [SwitchIndicatorContentStyle] {
        switch archetype {
        case .tileTwoLine, .lineWithBar, .switcher: [.iconAndText, .iconOnly, .textOnly]
        case .stackedText: [.textOnly]
        case .tileOnly, .badge: [.iconOnly]
        }
    }

    public static func effective(
        _ stored: SwitchIndicatorContentStyle,
        for archetype: BubbleArchetype
    ) -> SwitchIndicatorContentStyle {
        let supported = supported(archetype)
        return supported.contains(stored) ? stored : supported[0]
    }
}

/// Every length the shared bubble view needs, in points, already multiplied by the
/// Size and Scale settings. The bubble itself is measured from its content; these
/// are the inputs of that layout, not a size table.
public struct BubbleMetrics: Equatable, Sendable {
    /// The switcher's glyphs and names have minimum sizes, so below this factor the cells
    /// would shrink under their own text and overlap.
    public static let switcherMinimumFactor = 0.90

    /// The badge's only text is its glyph, so legibility alone sets its floor: below
    /// this factor 13 pt falls under 9 pt, the smallest size anything in this family
    /// draws text at. It is not a layout budget, which is why it sits far under the
    /// switcher's 0.90.
    public static let badgeMinimumFactor = 0.70

    /// Exhaustive on purpose: a new archetype has to state whether it has a floor
    /// rather than inherit none by falling into a default.
    public static func minimumFactor(for archetype: BubbleArchetype) -> Double {
        switch archetype {
        case .switcher: switcherMinimumFactor
        case .badge: badgeMinimumFactor
        case .tileTwoLine, .lineWithBar, .stackedText, .tileOnly: 0
        }
    }

    /// The size the bubble really draws at, so the settings slider can show the truth
    /// instead of a number the archetype's floor then overrides.
    public static func effectiveFactor(_ factor: Double, archetype: BubbleArchetype) -> Double {
        max(SwitcherConfig.clampedSwitchIndicatorSizeFactor(factor), minimumFactor(for: archetype))
    }

    enum Base {
        static let tileSide = 32.0
        static let bareTileSide = 40.0
        static let titleSize = 13.0
        static let detailSize = 11.0
        static let monospacedDetailSize = 10.5
        static let stackedTitleSize = 20.0
        static let stackedDetailSize = 10.0
        static let titleLineFactor = 1.25
        static let detailLineFactor = 1.3
        static let textMinWidth = 44.0
        static let textMaxWidth = 168.0
        static let maxBubbleWidth = 320.0
        static let minimumTileRadius = 3.0
        static let shadowRadius = 18.0
        static let shadowOffset = 8.0
        static let lineVerticalPadding = 7.0
        static let stackedVerticalPadding = 9.0
        static let stackedRuleGap = 4.0
        static let switcherCellHeight = 46.0
        static let switcherPadding = 5.0
    }

    public let sizeFactor: Double
    public let inset: Double
    public let tileSide: Double
    public let tileRadius: Double
    public let bubbleRadius: Double
    public let gap: Double
    public let trailingPadding: Double
    public let titleSize: Double
    public let detailSize: Double
    public let titleLineHeight: Double
    public let detailLineHeight: Double
    public let textMinWidth: Double
    public let textMaxWidth: Double
    public let maxBubbleWidth: Double
    public let shadowMargin: Double
    /// Height of the bubble before any content grows it; caps the corner radius.
    public let baseHeight: Double

    public init(sizeFactor requested: Double, textScale: Double, theme: IndicatorTheme) {
        let archetype = theme.archetype
        let factor = Self.effectiveFactor(requested, archetype: archetype)
        let textFactor = factor * IndicatorTypography.clampedTextScale(textScale)
        let isStacked = archetype == .stackedText
        let baseDetail = isStacked ? Base.stackedDetailSize
            : theme.typography.utilityDesign == .monospaced ? Base.monospacedDetailSize : Base.detailSize

        sizeFactor = factor
        inset = theme.inset * factor
        switch archetype {
        case .tileTwoLine: tileSide = Base.tileSide * factor
        case .tileOnly: tileSide = Base.bareTileSide * factor
        case .lineWithBar, .stackedText, .switcher, .badge: tileSide = 0
        }
        gap = (archetype == .lineWithBar ? 8 : 10) * factor
        switch archetype {
        case .lineWithBar: trailingPadding = 13 * factor
        case .stackedText: trailingPadding = 12 * factor
        case .tileTwoLine, .tileOnly, .switcher: trailingPadding = 15 * factor
        // The badge's own inset is BadgeMetrics.padding; this carries the same number
        // so the public field is not a stray zero if anything ever reads it.
        case .badge: trailingPadding = BadgeMetrics.Base.padding * factor
        }
        titleSize = (isStacked ? Base.stackedTitleSize : Base.titleSize) * textFactor
        detailSize = baseDetail * textFactor
        titleLineHeight = titleSize * Base.titleLineFactor
        detailLineHeight = detailSize * Base.detailLineFactor
        textMinWidth = Base.textMinWidth * textFactor
        textMaxWidth = Base.textMaxWidth * textFactor
        // The switcher's width budget is fixed, so a larger bubble reaches the carousel sooner.
        maxBubbleWidth = archetype == .switcher ? Base.maxBubbleWidth : Base.maxBubbleWidth * factor
        shadowMargin = ((2 * Base.shadowRadius + Base.shadowOffset) * factor).rounded(.up)

        switch archetype {
        case .tileTwoLine:
            baseHeight = max(tileSide, titleLineHeight + detailLineHeight) + 2 * inset
        case .tileOnly:
            baseHeight = tileSide
        case .lineWithBar:
            baseHeight = titleLineHeight + 2 * Base.lineVerticalPadding * factor
        case .stackedText:
            baseHeight = titleLineHeight + detailLineHeight
                + (Base.stackedRuleGap + 2 * Base.stackedVerticalPadding) * factor
        case .switcher:
            baseHeight = (Base.switcherCellHeight + 2 * Base.switcherPadding) * factor
        case .badge:
            baseHeight = BadgeMetrics.bubbleHeight(factor: factor, textFactor: textFactor)
        }
        bubbleRadius = min(theme.cornerRadius * factor, baseHeight / 2)
        let concentric = max(Base.minimumTileRadius, theme.cornerRadius - theme.inset)
        let tileRadiusCap = (tileSide > 0 ? tileSide : baseHeight) / 2
        tileRadius = min((theme.tileCornerRadius ?? concentric) * factor, tileRadiusCap)
    }

    /// What each of the three retired Size buttons meant, kept so a file written
    /// before the two size controls were merged folds to the size it was drawing.
    static func factor(for size: SwitchIndicatorSize) -> Double {
        switch size {
        case .small: 0.82
        case .medium: 1.00
        case .large: 1.22
        }
    }
}
