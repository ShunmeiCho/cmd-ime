import Foundation

/// What the app knows about its surroundings when the bubble is drawn.
public struct IndicatorRenderContext: Equatable, Sendable {
    public var isDarkAppearance: Bool
    /// The system accent colour as "#RRGGBB".
    public var accentHex: String
    public var reduceTransparency: Bool
    public var increaseContrast: Bool

    public init(
        isDarkAppearance: Bool,
        accentHex: String,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.isDarkAppearance = isDarkAppearance
        self.accentHex = accentHex
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

public enum BubbleSubstrate: Equatable, Sendable {
    case glass(isDark: Bool, washOpacity: Double)
    /// No wash: the system material does its own lensing and adapts to what is behind it.
    case liquidGlass(isDark: Bool)
    case paper(hex: String)
    /// Glass under Reduce Transparency or Increase Contrast.
    case solid(hex: String)
    case none
}

/// Everything the shared bubble view draws, fully resolved: no view reads the
/// config, the theme or a colour rule on its own.
public struct BubbleRenderModel: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        public let symbol: SlotSymbol
        public let name: String
        public let fillHex: String
        public let glyphHex: String
    }

    public let themeID: String
    /// The stored theme id when it could not be found and the default was used.
    public let fellBackFromThemeID: String?
    public let archetype: BubbleArchetype
    /// Already coerced to what the archetype supports.
    public let display: SwitchIndicatorContentStyle
    public let substrate: BubbleSubstrate
    public let symbol: SlotSymbol
    public let title: String
    public let detail: String
    public let isRightToLeft: Bool
    public let tileFillHex: String?
    public let glyphHex: String
    public let titleHex: String
    public let detailHex: String
    public let detailOpacity: Double
    public let barHex: String?
    public let strokeOpacity: Double
    public let highlightStrength: Double
    public let shadowStrength: Double
    public let typography: IndicatorTypography
    public let metrics: BubbleMetrics
    /// Switcher only.
    public let cells: [Cell]
    public let activeIndex: Int
    public let previousIndex: Int?
}

public enum IndicatorBubbleResolver {
    public static let noSourceDetail = "No input method selected"

    /// Nil when `slotID` names no slot. A missing or unknown theme id resolves to the
    /// default built-in, so a config written before themes existed renders Glass with
    /// its stored Display, Size, Scale and Color.
    public static func model(
        config: SwitcherConfig,
        themes: [IndicatorTheme],
        sources: [InputSourceInfo],
        slotID: InputRole,
        previousSlotID: InputRole?,
        source: InputSourceInfo?,
        context: IndicatorRenderContext
    ) -> BubbleRenderModel? {
        guard let slot = config.slot(slotID), let activeIndex = config.slots.firstIndex(of: slot) else { return nil }
        let (theme, fellBackFrom) = resolvedTheme(id: config.switchIndicatorThemeID, in: themes)

        var slotSources = Dictionary(
            config.slots.compactMap { candidate in
                InputSourceMatcher.bestMatch(for: candidate.id, sources: sources, config: config)
                    .map { (candidate.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        if let source { slotSources[slotID] = source }
        let symbols = SlotSymbolResolver.symbols(for: config.slots, sources: slotSources)
        let titles = SlotTitleResolver.titles(for: config.slots, sources: slotSources)
        let symbol = symbols[slotID] ?? SlotSymbol(glyph: SlotSymbolResolver.unknownGlyph)

        let metrics = BubbleMetrics(
            sizeFactor: config.switchIndicatorSizeFactor,
            textScale: theme.typography.textScale,
            theme: theme
        )
        let display = IndicatorDisplayComposition.effective(config.switchIndicatorContentStyle, for: theme.archetype)
        let inks = BubbleInks(theme: theme, context: context, colorStyle: config.switchIndicatorColorStyle)
        let colors = inks.colors(for: slot, symbol: symbol, display: display, tileSide: metrics.tileSide)
        let isGlass = theme.surface == .glass

        return BubbleRenderModel(
            themeID: theme.id,
            fellBackFromThemeID: fellBackFrom,
            archetype: theme.archetype,
            display: display,
            substrate: inks.substrate,
            symbol: symbol,
            title: titles[slotID] ?? slot.name,
            detail: source?.localizedName ?? noSourceDetail,
            isRightToLeft: SlotTitleResolver.isRightToLeft(language: source?.primaryLanguage),
            tileFillHex: colors.tileFillHex,
            glyphHex: colors.glyphHex,
            titleHex: colors.titleHex,
            detailHex: inks.textHex,
            detailOpacity: inks.detailOpacity,
            barHex: colors.barHex,
            strokeOpacity: context.increaseContrast ? BubbleInks.increasedContrastStroke : theme.strokeOpacity,
            highlightStrength: isGlass && !context.increaseContrast ? theme.highlightStrength : 0,
            shadowStrength: theme.shadowStrength,
            typography: theme.typography,
            metrics: metrics,
            cells: theme.archetype == .switcher ? config.slots.map { member in
                let memberSymbol = symbols[member.id] ?? SlotSymbol(glyph: SlotSymbolResolver.unknownGlyph)
                let thumb = inks.colors(for: member, symbol: memberSymbol, display: display, tileSide: metrics.tileSide)
                return BubbleRenderModel.Cell(
                    symbol: memberSymbol,
                    name: titles[member.id] ?? member.name,
                    fillHex: thumb.tileFillHex ?? inks.textHex,
                    glyphHex: thumb.glyphHex
                )
            } : [],
            activeIndex: activeIndex,
            previousIndex: previousSlotID.flatMap { id in config.slots.firstIndex { $0.id == id } }
        )
    }

    static func resolvedTheme(id: String?, in themes: [IndicatorTheme]) -> (theme: IndicatorTheme, fellBackFrom: String?) {
        if let id, let match = themes.first(where: { $0.id == id }) { return (match, nil) }
        let fallback = themes.first { $0.id == BuiltInIndicatorThemes.defaultID } ?? BuiltInIndicatorThemes.glass
        return (fallback, id)
    }
}
