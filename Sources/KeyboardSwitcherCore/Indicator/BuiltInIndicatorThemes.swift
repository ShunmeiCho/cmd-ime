import Foundation

/// The themes that ship with the app. They are plain data, the same type a user
/// theme file decodes to, and are never written to disk.
public enum BuiltInIndicatorThemes {
    public static let defaultID = "builtin.glass"

    public static let all: [IndicatorTheme] = [
        glass, classic, paperOneInk, paperTwoInks, paperSlotInks, typographic, tile, line, switcher, switcherTint,
    ]

    /// Translucent glass, an opaque slot-coloured tile, a bright title over a dimmer source name.
    static let glass = IndicatorTheme(id: defaultID, name: "Glass")

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
