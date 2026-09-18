import Foundation

/// Assigns each ink its job for one theme in one context: which colour fills the
/// tile, bar or thumb, which one carries text, and what the glyph is drawn in.
struct BubbleInks {
    static let darkGlassBaseHex = "#1E1E22"
    static let lightGlassBaseHex = "#F2F2F4"
    static let darkNeutralHex = "#FFFFFF"
    static let lightNeutralHex = "#1D1D1F"
    static let monochromeGlassHex = "#8E8E93"
    static let darkDetailOpacity = 0.78
    static let lightDetailOpacity = 0.74
    static let increasedContrastStroke = 0.55
    /// A glyph drawn smaller than this counts as text, not as a large bold object.
    static let largeGlyphPointSize = 14.0
    static let smallGlyphLightnessDrop = 0.20
    static let singleGlyphTileRatio = 0.56
    static let doubleGlyphTileRatio = 0.42
    static let switcherGlyphSizes = (single: 17.0, double: 13.0)

    struct SlotColors: Equatable {
        let tileFillHex: String?
        let glyphHex: String
        let titleHex: String
        let barHex: String?
    }

    let theme: IndicatorTheme
    let colorStyle: SwitchIndicatorColorStyle
    let accentHex: String
    let isDark: Bool
    let substrate: BubbleSubstrate
    /// The opaque colour legibility is measured against; nil when there is no surface.
    let surfaceHex: String?
    let textHex: String
    let detailOpacity: Double

    init(theme: IndicatorTheme, context: IndicatorRenderContext, colorStyle: SwitchIndicatorColorStyle) {
        self.theme = theme
        self.colorStyle = colorStyle
        accentHex = context.accentHex
        switch theme.appearance {
        case .auto: isDark = context.isDarkAppearance
        case .dark: isDark = true
        case .light: isDark = false
        }
        let neutralHex = isDark ? Self.darkNeutralHex : Self.lightNeutralHex

        switch theme.surface {
        case .glass:
            let base = isDark ? Self.darkGlassBaseHex : Self.lightGlassBaseHex
            let isSolid = context.reduceTransparency || context.increaseContrast
            substrate = isSolid ? .solid(hex: base) : .glass(isDark: isDark, washOpacity: theme.washOpacity)
            surfaceHex = base
            textHex = theme.textInkHex ?? neutralHex
            detailOpacity = context.increaseContrast ? 1 : (isDark ? Self.darkDetailOpacity : Self.lightDetailOpacity)
        case .paper:
            let paper = theme.substrateHex ?? IndicatorTheme.defaultSubstrateHex
            substrate = .paper(hex: paper)
            surfaceHex = paper
            textHex = theme.textInkHex ?? IndicatorTheme.defaultPaperTextInkHex
            detailOpacity = context.increaseContrast ? 1 : DisplayTint.density(of: textHex, on: paper)
        case .none:
            substrate = .none
            surfaceHex = nil
            textHex = neutralHex
            detailOpacity = 1
        }
    }

    func colors(
        for slot: SwitchSlot,
        symbol: SlotSymbol,
        display: SwitchIndicatorContentStyle,
        tileSide: Double
    ) -> SlotColors {
        let tile = tile(for: slot, symbol: symbol, display: display, tileSide: tileSide)
        let slotHex = theme.colorSource == .slot ? slotColorHex(for: slot) : nil

        switch theme.archetype {
        case .stackedText:
            return SlotColors(tileFillHex: nil, glyphHex: textHex, titleHex: titleHex(slotHex, display), barHex: textHex)
        case .lineWithBar:
            let raw = slotHex ?? tile.fillHex
            return SlotColors(
                tileFillHex: nil,
                glyphHex: slotHex.map { legible($0, minimum: InkLegibility.textMinimum) } ?? textHex,
                titleHex: titleHex(slotHex, display),
                barHex: legible(raw, minimum: InkLegibility.objectMinimum)
            )
        case .tileTwoLine, .tileOnly, .switcher:
            return SlotColors(tileFillHex: tile.fillHex, glyphHex: tile.glyphHex, titleHex: titleHex(slotHex, display), barHex: nil)
        }
    }

    // MARK: - Jobs

    /// The colour the Color setting hands to the coloured job of a `slot` theme.
    private func slotColorHex(for slot: SwitchSlot) -> String {
        let monochrome = theme.surface == .paper ? textHex : Self.monochromeGlassHex
        let chosen = switch colorStyle {
        case .role, .custom: slot.tintHex
        case .accent: accentHex
        case .monochrome: monochrome
        }
        return IndicatorRGB.normalizedHex(chosen) ?? monochrome
    }

    private func tile(
        for slot: SwitchSlot,
        symbol: SlotSymbol,
        display: SwitchIndicatorContentStyle,
        tileSide: Double
    ) -> (fillHex: String, glyphHex: String) {
        let carriesText = carriesSmallText(symbol: symbol, display: display, tileSide: tileSide)
        if theme.colorSource == .inks {
            if case let .paper(paper) = substrate {
                // Printed tile: the glyph is knocked out to the paper. A tile ink that is
                // only an object colour cannot carry small text, so the text ink prints it.
                let ink = theme.tileInkHex ?? textHex
                let ratio = InkLegibility.contrast(ink, paper) ?? 0
                return (carriesText && ratio < InkLegibility.textMinimum ? textHex : ink, paper)
            }
            guard let ink = theme.tileInkHex ?? theme.textInkHex else {
                return isDark ? (Self.darkNeutralHex, DisplayTint.darkGlyphHex) : (Self.lightNeutralHex, Self.darkNeutralHex)
            }
            return glyphRule(fillHex: ink, carriesSmallText: carriesText)
        }
        let slotHex = slotColorHex(for: slot)
        // On paper the fill must stand out from the sheet; on glass a saturated tile is the point.
        let fill = theme.surface == .paper ? legible(slotHex, minimum: InkLegibility.objectMinimum) : slotHex
        return glyphRule(fillHex: fill, carriesSmallText: carriesText)
    }

    /// The smallest thing drawn in the glyph colour decides the rule: a glyph under the
    /// large size, the disambiguating mark, or the slot name on the switcher's thumb.
    private func carriesSmallText(symbol: SlotSymbol, display: SwitchIndicatorContentStyle, tileSide: Double) -> Bool {
        let isDouble = symbol.glyph.count > 1
        let pointSize = tileSide > 0
            ? tileSide * (isDouble ? Self.doubleGlyphTileRatio : Self.singleGlyphTileRatio)
            : (isDouble ? Self.switcherGlyphSizes.double : Self.switcherGlyphSizes.single)
        let namesTheThumb = theme.archetype == .switcher && display != .iconOnly
        return pointSize < Self.largeGlyphPointSize || symbol.mark != nil || namesTheThumb
    }

    private func glyphRule(fillHex: String, carriesSmallText: Bool) -> (fillHex: String, glyphHex: String) {
        let tile = carriesSmallText
            ? DisplayTint.tile(fillHex: fillHex, minimum: InkLegibility.textMinimum, maxLightnessDrop: Self.smallGlyphLightnessDrop)
            : DisplayTint.tile(fillHex: fillHex)
        return tile ?? (fillHex, DisplayTint.darkGlyphHex)
    }

    /// In a text-only layout the title is the coloured job; Mono keeps it in the text ink.
    private func titleHex(_ slotHex: String?, _ display: SwitchIndicatorContentStyle) -> String {
        guard display == .textOnly, colorStyle != .monochrome, let slotHex else { return textHex }
        return legible(slotHex, minimum: InkLegibility.textMinimum)
    }

    private func legible(_ hex: String, minimum: Double) -> String {
        guard let surfaceHex else { return hex }
        return DisplayTint.adjusted(hex, against: surfaceHex, minimum: minimum) ?? hex
    }
}
