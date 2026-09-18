import Foundation

public struct Substrate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let hex: String
}

public struct Ink: Equatable, Sendable {
    public let id: String
    public let name: String
    public let hex: String
}

public struct InkPair: Equatable, Sendable {
    public let id: String
    public let inkIDs: [String]
}

/// The job each member of a two-ink pair takes on one substrate.
public struct InkJobs: Equatable, Sendable {
    public let textInk: Ink
    public let tileInk: Ink
}

/// Paper substrates, printing inks and approved two-ink pairs. The hex values are
/// the ones published by the mono-color design system; nothing else of it ships.
public enum InkCatalog {
    public static let substrates: [Substrate] = [
        Substrate(id: "white", name: "Neutral White", hex: "#FAFAF7"),
        Substrate(id: "gray", name: "Cool Gray", hex: "#E9E9E5"),
        Substrate(id: "beige", name: "Pale Beige", hex: "#F5F1E8"),
    ]

    public static let inks: [Ink] = [
        Ink(id: "cobalt", name: "Cobalt", hex: "#2148B8"),
        Ink(id: "royalBlue", name: "Royal Blue", hex: "#2058D4"),
        Ink(id: "botanicalGreen", name: "Botanical Green", hex: "#008A4B"),
        Ink(id: "mintGreen", name: "Mint Green", hex: "#5EB783"),
        Ink(id: "terracotta", name: "Terracotta Orange", hex: "#C65F38"),
        Ink(id: "signalRed", name: "Signal Red", hex: "#C83232"),
        Ink(id: "aubergine", name: "Aubergine", hex: "#63365F"),
        Ink(id: "charcoal", name: "Charcoal", hex: "#30343A"),
        Ink(id: "powderBlue", name: "Powder Blue", hex: "#9EB8D3"),
        Ink(id: "oxblood", name: "Oxblood", hex: "#8F3434"),
        Ink(id: "electricBlue", name: "Electric Blue", hex: "#173AE3"),
        Ink(id: "carbon", name: "Carbon", hex: "#242321"),
        // The source palette files this ink under the id "ink_mint_charcoal".
        Ink(id: "warmCharcoal", name: "Warm Charcoal", hex: "#302D2E"),
        Ink(id: "ultramarine", name: "Ultramarine", hex: "#263E99"),
        Ink(id: "safetyOrange", name: "Safety Orange", hex: "#E55D2B"),
        Ink(id: "cyan", name: "Cyan", hex: "#159DDA"),
        Ink(id: "brickRed", name: "Brick Red", hex: "#B64032"),
        Ink(id: "tangerine", name: "Tangerine", hex: "#E46C2D"),
        Ink(id: "slateBlue", name: "Slate Blue", hex: "#4773A5"),
    ]

    public static let pairs: [InkPair] = [
        InkPair(id: "charcoal-signalRed", inkIDs: ["charcoal", "signalRed"]),
        InkPair(id: "cobalt-terracotta", inkIDs: ["cobalt", "terracotta"]),
        InkPair(id: "ultramarine-safetyOrange", inkIDs: ["ultramarine", "safetyOrange"]),
        InkPair(id: "botanicalGreen-oxblood", inkIDs: ["botanicalGreen", "oxblood"]),
        InkPair(id: "cyan-brickRed", inkIDs: ["cyan", "brickRed"]),
        InkPair(id: "mintGreen-warmCharcoal", inkIDs: ["mintGreen", "warmCharcoal"]),
    ]

    public static func ink(_ id: String) -> Ink? {
        inks.first { $0.id == id }
    }

    public static func substrate(_ id: String) -> Substrate? {
        substrates.first { $0.id == id }
    }
}

/// WCAG contrast rules that decide which ink may carry which job on a substrate.
public enum InkLegibility {
    /// WCAG 1.4.3, body text.
    public static let textMinimum = 4.5
    /// WCAG 1.4.11, objects and the large bold tile glyph.
    public static let objectMinimum = 3.0

    /// Contrast ratio between two "#RRGGBB" colours; nil when either is malformed.
    public static func contrast(_ a: String, _ b: String) -> Double? {
        guard let first = IndicatorRGB(hex: a), let second = IndicatorRGB(hex: b) else { return nil }
        return first.contrast(with: second)
    }

    public static func textInks(on substrateHex: String) -> [Ink] {
        inks(on: substrateHex, minimum: textMinimum)
    }

    public static func tileInks(on substrateHex: String) -> [Ink] {
        inks(on: substrateHex, minimum: objectMinimum)
    }

    /// The member with the higher contrast carries the text, the other the tile.
    /// Nil when the pair is not legible on this substrate: the tile's knocked-out
    /// glyph is drawn in the substrate colour, so one ratio covers tile and glyph.
    public static func assignment(for pair: InkPair, on substrateHex: String) -> InkJobs? {
        let members = pair.inkIDs.compactMap(InkCatalog.ink)
        guard pair.inkIDs.count == 2, members.count == 2,
              let first = contrast(members[0].hex, substrateHex),
              let second = contrast(members[1].hex, substrateHex) else { return nil }
        let jobs = first >= second
            ? (text: members[0], textRatio: first, tile: members[1], tileRatio: second)
            : (text: members[1], textRatio: second, tile: members[0], tileRatio: first)
        guard jobs.textRatio >= textMinimum, jobs.tileRatio >= objectMinimum else { return nil }
        return InkJobs(textInk: jobs.text, tileInk: jobs.tile)
    }

    private static func inks(on substrateHex: String, minimum: Double) -> [Ink] {
        InkCatalog.inks.filter { ink in
            (contrast(ink.hex, substrateHex) ?? 0) >= minimum
        }
    }
}
