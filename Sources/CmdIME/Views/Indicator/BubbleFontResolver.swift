import CoreText
import KeyboardSwitcherCore
import SwiftUI

/// Turns a theme's typography into fonts. The display voice (title, tile glyph) may
/// use a custom family; the utility voice (detail line, names, marks) is always a
/// system design. A family that cannot be found falls back to the theme's system
/// design, so the bubble never fails to draw.
enum BubbleFontResolver {
    static func display(_ typography: IndicatorTypography, size: CGFloat, weight: IndicatorFontWeight? = nil) -> Font {
        let weight = weight ?? typography.displayWeight
        if let family = typography.displayFamily, let font = customFont(family: family, weight: weight, size: size) {
            return Font(font)
        }
        return .system(size: size, weight: fontWeight(weight), design: fontDesign(typography.displayDesign))
    }

    static func utility(_ typography: IndicatorTypography, size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: typography.utilityDesign == .monospaced ? .monospaced : .default)
    }

    static func isAvailable(family: String) -> Bool {
        customFont(family: family, weight: .regular, size: 12) != nil
    }

    /// True when the family has a face at the requested weight, not only a nearest match.
    static func hasExactWeight(family: String, weight: IndicatorFontWeight) -> Bool {
        guard let font = customFont(family: family, weight: weight, size: 12),
              let traits = CTFontCopyTraits(font) as? [CFString: Any],
              let actual = traits[kCTFontWeightTrait] as? Double else { return true }
        return abs(actual - coreTextWeight(weight)) < 0.12
    }

    /// CoreText sees fonts registered for this process, so imported families resolve
    /// here. The match is checked because CoreText substitutes a missing family silently.
    private static func customFont(family: String, weight: IndicatorFontWeight, size: CGFloat) -> CTFont? {
        let traits: [CFString: Any] = [kCTFontWeightTrait: coreTextWeight(weight)]
        let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family, kCTFontTraitsAttribute: traits]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let resolved = CTFontCopyFamilyName(font) as String
        return resolved.caseInsensitiveCompare(family) == .orderedSame ? font : nil
    }

    private static func coreTextWeight(_ weight: IndicatorFontWeight) -> Double {
        switch weight {
        case .regular: 0.0
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        }
    }

    static func fontWeight(_ weight: IndicatorFontWeight) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    private static func fontDesign(_ design: IndicatorFontDesign) -> Font.Design {
        switch design {
        case .default: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}
