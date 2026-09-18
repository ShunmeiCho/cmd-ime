import Foundation

public enum BubbleArchetype: String, Codable, CaseIterable, Sendable {
    case tileTwoLine, lineWithBar, stackedText, tileOnly, switcher
}

public enum IndicatorSurface: String, Codable, CaseIterable, Sendable {
    case glass, paper, none
}

public enum IndicatorAppearance: String, Codable, CaseIterable, Sendable {
    case auto, dark, light
}

/// `slot` colours the tile, bar or thumb from the Color setting; `inks` prints
/// with the theme's own inks and ignores slot colours.
public enum IndicatorColorSource: String, Codable, CaseIterable, Sendable {
    case slot, inks
}

public enum IndicatorThemeIssue: Error, Equatable, Sendable {
    case unreadable(String)
    case notJSON
    case unsupportedSchema(Int)
    case invalidHex(key: String, value: String)
    case unknownValue(key: String, value: String)
    case incompatible(key: String, with: String)
    case reservedID(String)
    case duplicateID(String)

    public var message: String {
        switch self {
        case let .unreadable(reason): "The theme could not be read: \(reason)"
        case .notJSON: "The file is not valid JSON."
        case let .unsupportedSchema(version): "Theme schema \(version) is not supported by this version of CmdIME."
        case let .invalidHex(key, value): "\(key) must be a colour such as #2148B8, not \(value.debugDescription)."
        case let .unknownValue(key, value): "\(key) has the unknown value \(value.debugDescription)."
        case let .incompatible(key, other): "This \(key) cannot be combined with this \(other)."
        case let .reservedID(id): "The id \(id.debugDescription) is reserved for built-in themes."
        case let .duplicateID(id): "Another theme already uses the id \(id.debugDescription)."
        }
    }
}

/// Everything that decides how the switch indicator looks. Built-in and user
/// themes are the same type; user themes are one JSON file each.
public struct IndicatorTheme: Codable, Equatable, Identifiable, Sendable {
    public static let schemaVersion = 1
    public static let builtInPrefix = "builtin."
    public static let maxFileBytes = 64 * 1024
    public static let maxIDLength = 64
    public static let maxNameGraphemes = 40
    public static let defaultSubstrateHex = "#FAFAF7"
    public static let defaultPaperTextInkHex = "#242321"

    /// Clamp range and default of every numeric field.
    public enum Limits {
        public static let cornerRadius = (range: 0.0...28.0, fallback: 16.0)
        public static let tileCornerRadius = 0.0...20.0
        public static let inset = (range: 4.0...16.0, fallback: 9.0)
        public static let strokeOpacity = (range: 0.0...1.0, fallback: 0.16)
        public static let washOpacity = (range: 0.0...0.9, fallback: 0.45)
        public static let highlightStrength = (range: 0.0...1.0, fallback: 1.0)
        public static let shadowStrength = (range: 0.0...1.0, fallback: 0.6)
    }

    public var id: String
    public var name: String
    public var archetype: BubbleArchetype
    public var surface: IndicatorSurface
    /// Glass only.
    public var appearance: IndicatorAppearance
    public var colorSource: IndicatorColorSource
    public var substrateHex: String?
    /// Nil on glass means the neutral label colour.
    public var textInkHex: String?
    /// Nil means the text ink. Ignored while `colorSource` is `slot`.
    public var tileInkHex: String?
    public var cornerRadius: Double
    /// Nil keeps the tile concentric with the bubble.
    public var tileCornerRadius: Double?
    public var inset: Double
    public var strokeOpacity: Double
    public var washOpacity: Double
    public var highlightStrength: Double
    public var shadowStrength: Double
    public var typography: IndicatorTypography

    public var isBuiltIn: Bool { id.hasPrefix(Self.builtInPrefix) }

    /// Numbers are clamped and non-finite ones take their default. Colours are
    /// stored as given; files are validated by `decoding(_:fileName:)`.
    public init(
        id: String,
        name: String,
        archetype: BubbleArchetype = .tileTwoLine,
        surface: IndicatorSurface = .glass,
        appearance: IndicatorAppearance = .auto,
        colorSource: IndicatorColorSource = .slot,
        substrateHex: String? = nil,
        textInkHex: String? = nil,
        tileInkHex: String? = nil,
        cornerRadius: Double = Limits.cornerRadius.fallback,
        tileCornerRadius: Double? = nil,
        inset: Double = Limits.inset.fallback,
        strokeOpacity: Double = Limits.strokeOpacity.fallback,
        washOpacity: Double = Limits.washOpacity.fallback,
        highlightStrength: Double = Limits.highlightStrength.fallback,
        shadowStrength: Double = Limits.shadowStrength.fallback,
        typography: IndicatorTypography = IndicatorTypography()
    ) {
        self.id = id
        self.name = name
        self.archetype = archetype
        self.surface = surface
        self.appearance = appearance
        self.colorSource = colorSource
        self.substrateHex = substrateHex ?? (surface == .paper ? Self.defaultSubstrateHex : nil)
        self.textInkHex = textInkHex ?? (surface == .paper ? Self.defaultPaperTextInkHex : nil)
        self.tileInkHex = tileInkHex
        self.cornerRadius = Self.clamped(cornerRadius, Limits.cornerRadius)
        self.tileCornerRadius = tileCornerRadius.flatMap { radius in
            radius.isFinite ? min(max(radius, Limits.tileCornerRadius.lowerBound), Limits.tileCornerRadius.upperBound) : nil
        }
        self.inset = Self.clamped(inset, Limits.inset)
        self.strokeOpacity = Self.clamped(strokeOpacity, Limits.strokeOpacity)
        self.washOpacity = Self.clamped(washOpacity, Limits.washOpacity)
        self.highlightStrength = Self.clamped(highlightStrength, Limits.highlightStrength)
        self.shadowStrength = Self.clamped(shadowStrength, Limits.shadowStrength)
        self.typography = typography
    }

    private static func clamped(_ value: Double, _ limit: (range: ClosedRange<Double>, fallback: Double)) -> Double {
        guard value.isFinite else { return limit.fallback }
        return min(max(value, limit.range.lowerBound), limit.range.upperBound)
    }

    /// Lowercase `[a-z0-9-]`, at most 64 characters; nil when nothing usable is left.
    public static func sanitizedID(_ raw: String) -> String? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let words = raw.lowercased().split(whereSeparator: { !allowed.contains($0) })
        let id = String(words.joined(separator: "-").prefix(maxIDLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return id.isEmpty ? nil : id
    }
}

// MARK: - File codec

extension IndicatorTheme {
    static let fileNameKey = CodingUserInfoKey(rawValue: "IndicatorTheme.fileName")!

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, archetype, surface, appearance, colorSource
        case substrateHex, textInkHex, tileInkHex
        case cornerRadius, tileCornerRadius, inset, strokeOpacity, washOpacity, highlightStrength, shadowStrength
        case typography
    }

    /// Validates one theme file. Unknown keys are ignored; an unknown enum value, a
    /// malformed colour or an impossible combination rejects the file with a named issue.
    public static func decoding(_ data: Data, fileName: String) -> Result<IndicatorTheme, IndicatorThemeIssue> {
        guard data.count <= maxFileBytes else {
            return .failure(.unreadable("the file is larger than \(maxFileBytes / 1024) KB"))
        }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return .failure(.notJSON) }
        let decoder = JSONDecoder()
        decoder.userInfo[fileNameKey] = fileName
        do {
            return .success(try decoder.decode(IndicatorTheme.self, from: data))
        } catch let issue as IndicatorThemeIssue {
            return .failure(issue)
        } catch let DecodingError.keyNotFound(key, _) {
            return .failure(.unreadable("\(key.stringValue) is missing"))
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return .failure(.unreadable("\(path) has the wrong type"))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else { throw IndicatorThemeIssue.unsupportedSchema(version) }

        let fileStem = (decoder.userInfo[Self.fileNameKey] as? String)
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        let rawID = try container.decodeIfPresent(String.self, forKey: .id) ?? fileStem ?? ""
        guard !rawID.lowercased().hasPrefix(Self.builtInPrefix) else { throw IndicatorThemeIssue.reservedID(rawID) }
        guard let id = Self.sanitizedID(rawID) else { throw IndicatorThemeIssue.unreadable("id is empty") }

        let archetype: BubbleArchetype = try container.indicatorValue(forKey: .archetype) ?? .tileTwoLine
        let surface: IndicatorSurface = try container.indicatorValue(forKey: .surface) ?? .glass
        guard surface != .none || archetype == .tileOnly else {
            throw IndicatorThemeIssue.incompatible(key: "surface", with: "archetype")
        }

        let name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        func hex(_ key: CodingKeys) throws -> String? {
            guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
            guard let normalized = IndicatorRGB.normalizedHex(raw) else {
                throw IndicatorThemeIssue.invalidHex(key: key.stringValue, value: raw)
            }
            return normalized
        }
        func number(_ key: CodingKeys) throws -> Double? {
            try container.decodeIfPresent(Double.self, forKey: key)
        }

        self.init(
            id: id,
            name: name.isEmpty ? id : String(name.prefix(Self.maxNameGraphemes)),
            archetype: archetype,
            surface: surface,
            appearance: try container.indicatorValue(forKey: .appearance) ?? .auto,
            colorSource: try container.indicatorValue(forKey: .colorSource) ?? .slot,
            substrateHex: try hex(.substrateHex),
            textInkHex: try hex(.textInkHex),
            tileInkHex: try hex(.tileInkHex),
            cornerRadius: try number(.cornerRadius) ?? Limits.cornerRadius.fallback,
            tileCornerRadius: try number(.tileCornerRadius),
            inset: try number(.inset) ?? Limits.inset.fallback,
            strokeOpacity: try number(.strokeOpacity) ?? Limits.strokeOpacity.fallback,
            washOpacity: try number(.washOpacity) ?? Limits.washOpacity.fallback,
            highlightStrength: try number(.highlightStrength) ?? Limits.highlightStrength.fallback,
            shadowStrength: try number(.shadowStrength) ?? Limits.shadowStrength.fallback,
            typography: try container.decodeIfPresent(IndicatorTypography.self, forKey: .typography)
                ?? IndicatorTypography()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(archetype, forKey: .archetype)
        try container.encode(surface, forKey: .surface)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(colorSource, forKey: .colorSource)
        try container.encodeIfPresent(substrateHex, forKey: .substrateHex)
        try container.encodeIfPresent(textInkHex, forKey: .textInkHex)
        try container.encodeIfPresent(tileInkHex, forKey: .tileInkHex)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(tileCornerRadius, forKey: .tileCornerRadius)
        try container.encode(inset, forKey: .inset)
        try container.encode(strokeOpacity, forKey: .strokeOpacity)
        try container.encode(washOpacity, forKey: .washOpacity)
        try container.encode(highlightStrength, forKey: .highlightStrength)
        try container.encode(shadowStrength, forKey: .shadowStrength)
        try container.encode(typography, forKey: .typography)
    }
}

// MARK: - Legibility

/// Advisory contrast report for a theme's own inks. Saving is never blocked by it.
public enum IndicatorThemeLegibility {
    public struct Issue: Equatable, Sendable {
        public let key: String
        public let ratio: Double
        public let minimum: Double
    }

    public static func issues(_ theme: IndicatorTheme) -> [Issue] {
        guard theme.surface == .paper, let substrate = theme.substrateHex else { return [] }
        let text = theme.textInkHex.flatMap { InkLegibility.contrast($0, substrate) }
            .map { Issue(key: "textInkHex", ratio: $0, minimum: InkLegibility.textMinimum) }
        let tile = theme.colorSource == .inks
            ? theme.tileInkHex.flatMap { InkLegibility.contrast($0, substrate) }
                .map { Issue(key: "tileInkHex", ratio: $0, minimum: InkLegibility.objectMinimum) }
            : nil
        return [text, tile].compactMap { $0 }.filter { $0.ratio < $0.minimum }
    }
}
