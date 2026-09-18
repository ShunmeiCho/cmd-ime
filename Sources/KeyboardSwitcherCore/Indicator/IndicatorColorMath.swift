import Foundation

/// sRGB colour helpers shared by the indicator model. Components are 0...1.
struct IndicatorRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = IndicatorRGB(red: 1, green: 1, blue: 1)
    static let black = IndicatorRGB(red: 0, green: 0, blue: 0)

    /// Accepts six hexadecimal digits with an optional leading "#".
    init?(hex: String) {
        guard let normalized = Self.normalizedHex(hex) else { return nil }
        let digits = Array(normalized.utf8.dropFirst())
        let components = stride(from: 0, to: 6, by: 2).map { offset in
            Double(Self.nibble(digits[offset]) * 16 + Self.nibble(digits[offset + 1])) / 255
        }
        self.init(red: components[0], green: components[1], blue: components[2])
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Uppercase "#RRGGBB", or nil when the input is not a six-digit hex colour.
    static func normalizedHex(_ input: String) -> String? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.utf8.count == 6,
              hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        return "#" + hex.uppercased()
    }

    /// Value of one ASCII hexadecimal digit that `normalizedHex` has validated.
    private static func nibble(_ digit: UInt8) -> Int {
        digit <= 57 ? Int(digit) - 48 : Int(digit) - 55
    }

    var hex: String {
        let bytes = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    /// The colour as it survives a round trip through eight-bit hex, so a contrast
    /// measured on a candidate is the contrast of the hex that is returned.
    var quantized: IndicatorRGB {
        IndicatorRGB(
            red: (red * 255).rounded() / 255,
            green: (green * 255).rounded() / 255,
            blue: (blue * 255).rounded() / 255
        )
    }

    /// WCAG 2 relative luminance.
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1...21.
    func contrast(with other: IndicatorRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This colour at `alpha` composited over an opaque backdrop.
    func composited(over backdrop: IndicatorRGB, alpha: Double) -> IndicatorRGB {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return IndicatorRGB(
            red: mix(red, backdrop.red),
            green: mix(green, backdrop.green),
            blue: mix(blue, backdrop.blue)
        )
    }

    /// Hue in degrees 0..<360, saturation and lightness 0...1.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        let sector: Double
        if maximum == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        let hue = (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
        return (hue, min(saturation, 1), lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch sector {
        case ..<1: base = (chroma, second, 0)
        case ..<2: base = (second, chroma, 0)
        case ..<3: base = (0, chroma, second)
        case ..<4: base = (0, second, chroma)
        case ..<5: base = (second, 0, chroma)
        default: base = (chroma, 0, second)
        }
        let offset = lightness - chroma / 2
        self.init(red: base.0 + offset, green: base.1 + offset, blue: base.2 + offset)
    }
}
