import Foundation

/// The themes that ship with the app. They are plain data, the same type a user
/// theme file decodes to, and are never written to disk.
public enum BuiltInIndicatorThemes {
    /// The switcher shows every slot with its name, so a first appearance teaches
    /// which glyph belongs to which slot. The badge is what that becomes once the
    /// mapping is known, and it is one click away in the picker.
    public static let defaultID = "builtin.switcher"
    /// What the default used to be. A config written before the default changed is
    /// pinned to it on load, so nobody's indicator changes under them.
    public static let legacyDefaultID = "builtin.glass"

    public static let all: [IndicatorTheme] = [
        switcher, switcherTint, switcherLiquid, badge, badgeTint,
        glass, liquidGlass, classic, paperOneInk, paperTwoInks, paperSlotInks, typographic, tile, line,
    ]

    /// The caret badge: the switcher's row shrunk to glyph-sized cells, in the system
    /// material with almost no edge, so it reads as a mark beside the caret rather than
    /// a panel over the page. Its thumb is the neutral of the appearance, translucent.
    static let badge = IndicatorTheme(
        id: "builtin.badge",
        name: "Badge",
        archetype: .badge,
        surface: .liquidGlass,
        colorSource: .inks,
        cornerRadius: 14,
        strokeOpacity: 0.10,
        washOpacity: 0,
        highlightStrength: 0,
        shadowStrength: 0.30
    )

    /// The same badge carrying the Color setting. A slot-tinted thumb cannot also be
    /// translucent and still hold the text contrast minimum, so this one is opaque.
    static let badgeTint = IndicatorTheme(
        id: "builtin.badge-tint",
        name: "Badge, Slot Color",
        archetype: .badge,
        surface: .liquidGlass,
        cornerRadius: 14,
        strokeOpacity: 0.10,
        washOpacity: 0,
        highlightStrength: 0,
        shadowStrength: 0.30
    )

    /// Translucent glass, an opaque slot-coloured tile, a bright title over a dimmer source name.
    static let glass = IndicatorTheme(id: legacyDefaultID, name: "Glass")

    /// The macOS 26 system material. No wash or drawn highlight: the material supplies both.
    static let liquidGlass = IndicatorTheme(
        id: "builtin.liquid-glass", name: "Liquid Glass", surface: .liquidGlass,
        washOpacity: 0, highlightStrength: 0
    )

    static let switcherLiquid = IndicatorTheme(
        id: "builtin.switcher-liquid", name: "Switcher, Liquid", archetype: .switcher, surface: .liquidGlass,
        washOpacity: 0, highlightStrength: 0
    )

    /// The bubble as it looked before themes: no wash, no top highlight, rounder corners.
    static let classic = IndicatorTheme(
        id: "builtin.classic",
        name: "Classic",
        cornerRadius: 18,
        tileCornerRadius: 9,
        inset: 11,
        strokeOpacity: 0.18,
        washOpacity: 0,
        highlightStrength: 0,
        shadowStrength: 0.5
    )

    static let paperOneInk = paper(
        id: "builtin.paper-one-ink", name: "Paper, One Ink",
        substrate: "white", colorSource: .inks, textInk: "cobalt"
    )

    static let paperTwoInks = paper(
        id: "builtin.paper-two-inks", name: "Paper, Two Inks",
        substrate: "white", colorSource: .inks, textInk: "cobalt", tileInk: "terracotta"
    )

    static let paperSlotInks = paper(
        id: "builtin.paper-slots", name: "Paper, Slot Inks",
        substrate: "gray", colorSource: .slot, textInk: "carbon"
    )

    static let typographic = paper(
        id: "builtin.typographic", name: "Typographic",
        archetype: .stackedText, substrate: "beige", colorSource: .inks, textInk: "aubergine", preset: .literary
    )

    static let tile = IndicatorTheme(
        id: "builtin.tile", name: "Tile",
        archetype: .tileOnly, surface: .none, cornerRadius: 11, tileCornerRadius: 11
    )

    static let line = IndicatorTheme(id: "builtin.line", name: "Line", archetype: .lineWithBar)

    static let switcher = IndicatorTheme(
        id: "builtin.switcher", name: "Switcher", archetype: .switcher, colorSource: .inks
    )

    static let switcherTint = IndicatorTheme(
        id: "builtin.switcher-tint", name: "Switcher, Slot Color", archetype: .switcher
    )

    /// Paper is cut, not moulded: small radii, a hairline of the text ink, no highlight.
    private static func paper(
        id: String,
        name: String,
        archetype: BubbleArchetype = .tileTwoLine,
        substrate: String,
        colorSource: IndicatorColorSource,
        textInk: String,
        tileInk: String? = nil,
        preset: TypographyPreset = .programmatic
    ) -> IndicatorTheme {
        IndicatorTheme(
            id: id,
            name: name,
            archetype: archetype,
            surface: .paper,
            colorSource: colorSource,
            substrateHex: InkCatalog.substrate(substrate)?.hex,
            textInkHex: InkCatalog.ink(textInk)?.hex,
            tileInkHex: tileInk.flatMap(InkCatalog.ink)?.hex,
            cornerRadius: 6,
            tileCornerRadius: 3,
            highlightStrength: 0,
            typography: preset.typography
        )
    }
}
