import Foundation

/// Derives the colour that is drawn from the colour that is stored. Stored
/// values are never rewritten; only what reaches the screen is adjusted.
public enum DisplayTint {
    public static let darkGlyphHex = "#1A1A1C"
    static let lightGlyphHex = "#FFFFFF"
    /// Surfaces darker than this get a lighter tint, all others a darker one.
    static let darkSurfaceLuminance = 0.18
    static let lightnessStep = 0.01

    /// Returns `hex` unchanged when it already reaches `minimum` against the
    /// surface. Otherwise moves HSL lightness away from the surface, keeping hue
    /// and saturation, and returns the first candidate that passes; pure white or
    /// black when none does. Nil when either colour is malformed.
    public static func adjusted(_ hex: String, against surfaceHex: String, minimum: Double) -> String? {
        guard let color = IndicatorRGB(hex: hex), let surface = IndicatorRGB(hex: surfaceHex) else { return nil }
        if color.contrast(with: surface) >= minimum { return color.hex }

        let lightens = surface.relativeLuminance < darkSurfaceLuminance
        let (hue, saturation, lightness) = color.hsl
        var step = 1
        while true {
            let moved = lightness + Double(step) * lightnessStep * (lightens ? 1 : -1)
            guard (0...1).contains(moved) else { break }
            let candidate = IndicatorRGB(hue: hue, saturation: saturation, lightness: moved).quantized
            if candidate.contrast(with: surface) >= minimum { return candidate.hex }
            step += 1
        }
        return lightens ? IndicatorRGB.white.hex : IndicatorRGB.black.hex
    }

    /// A white glyph is kept when it reaches `minimum` on the fill, if needed by
    /// lowering the fill's HSL lightness by at most `maxLightnessDrop`. Beyond
    /// that the stored fill is kept and the glyph turns dark.
    public static func tile(
        fillHex: String,
        minimum: Double = 3.0,
        maxLightnessDrop: Double = 0.10
    ) -> (fillHex: String, glyphHex: String)? {
        guard let fill = IndicatorRGB(hex: fillHex) else { return nil }
        if IndicatorRGB.white.contrast(with: fill) >= minimum { return (fill.hex, lightGlyphHex) }

        let (hue, saturation, lightness) = fill.hsl
        let maxSteps = Int((maxLightnessDrop / lightnessStep).rounded())
        for step in stride(from: 1, through: max(maxSteps, 0), by: 1) {
            let candidate = IndicatorRGB(
                hue: hue,
                saturation: saturation,
                lightness: max(lightness - Double(step) * lightnessStep, 0)
            ).quantized
            if IndicatorRGB.white.contrast(with: candidate) >= minimum { return (candidate.hex, lightGlyphHex) }
        }
        return (fill.hex, darkGlyphHex)
    }

    /// The smallest alpha, in 0.01 steps and never under `floor`, at which the ink
    /// printed over the surface still reaches `minimum`. 1.0 when the ink cannot
    /// be thinned (it fails at full strength, or a colour is malformed).
    public static func density(
        of inkHex: String,
        on surfaceHex: String,
        minimum: Double = 4.5,
        floor: Double = 0.72
    ) -> Double {
        guard let ink = IndicatorRGB(hex: inkHex), let surface = IndicatorRGB(hex: surfaceHex) else { return 1 }
        let firstStep = Int((min(max(floor, 0), 1) * 100).rounded())
        for percent in stride(from: firstStep, to: 100, by: 1) {
            let alpha = Double(percent) / 100
            if ink.composited(over: surface, alpha: alpha).contrast(with: surface) >= minimum { return alpha }
        }
        return 1
    }
}
