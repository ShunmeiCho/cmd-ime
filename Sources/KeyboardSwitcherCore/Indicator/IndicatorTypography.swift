import Foundation

public enum IndicatorFontDesign: String, Codable, CaseIterable, Sendable {
    case `default`, rounded, serif, monospaced
}

/// Thin weights are left out: their strokes lose contrast over a translucent surface.
public enum IndicatorFontWeight: String, Codable, CaseIterable, Sendable {
    case regular, medium, semibold, bold, heavy
}

public enum IndicatorUtilityDesign: String, Codable, CaseIterable, Sendable {
    case `default`, monospaced
}

/// One display voice (title and tile glyph) plus one utility voice (detail line,
/// switcher names, marks). Only the display voice can take a custom family.
public struct IndicatorTypography: Codable, Equatable, Sendable {
    public static let defaultTextScale = 1.0
    public static let minTextScale = 0.8
    public static let maxTextScale = 1.6

    /// Nil follows `displayDesign`. Availability is checked when the bubble is drawn.
    public var displayFamily: String?
    /// Ignored while a family is set.
    public var displayDesign: IndicatorFontDesign
    public var displayWeight: IndicatorFontWeight
    public var utilityDesign: IndicatorUtilityDesign
    public var textScale: Double

    public init(
        displayFamily: String? = nil,
        displayDesign: IndicatorFontDesign = .default,
        displayWeight: IndicatorFontWeight = .semibold,
        utilityDesign: IndicatorUtilityDesign = .default,
        textScale: Double = IndicatorTypography.defaultTextScale
    ) {
        self.displayFamily = Self.normalizedFamily(displayFamily)
        self.displayDesign = displayDesign
        self.displayWeight = displayWeight
        self.utilityDesign = utilityDesign
        self.textScale = Self.clampedTextScale(textScale)
    }

    public static func clampedTextScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTextScale }
        return min(max(value, minTextScale), maxTextScale)
    }

    private static func normalizedFamily(_ family: String?) -> String? {
        let trimmed = family?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private enum CodingKeys: String, CodingKey {
        case displayFamily, displayDesign, displayWeight, utilityDesign, textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displayFamily: try container.decodeIfPresent(String.self, forKey: .displayFamily),
            displayDesign: try container.indicatorValue(forKey: .displayDesign, prefix: "typography.") ?? .default,
            displayWeight: try container.indicatorValue(forKey: .displayWeight, prefix: "typography.") ?? .semibold,
            utilityDesign: try container.indicatorValue(forKey: .utilityDesign, prefix: "typography.") ?? .default,
            textScale: try container.decodeIfPresent(Double.self, forKey: .textScale) ?? Self.defaultTextScale
        )
    }
}

/// The type pairings the built-in themes use.
public enum TypographyPreset: String, CaseIterable, Sendable {
    case system
    case programmatic
    case literary

    public var typography: IndicatorTypography {
        switch self {
        case .system:
            IndicatorTypography()
        case .programmatic:
            IndicatorTypography(displayWeight: .medium, utilityDesign: .monospaced)
        case .literary:
            IndicatorTypography(displayDesign: .serif)
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a string-backed enum, reporting an unknown raw value as a theme issue
    /// that names the offending key instead of a generic decoding error.
    func indicatorValue<Value: RawRepresentable>(
        forKey key: Key,
        prefix: String = ""
    ) throws -> Value? where Value.RawValue == String {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let value = Value(rawValue: raw) else {
            throw IndicatorThemeIssue.unknownValue(key: prefix + key.stringValue, value: raw)
        }
        return value
    }
}
