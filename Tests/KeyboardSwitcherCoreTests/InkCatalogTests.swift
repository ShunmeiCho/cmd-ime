import XCTest
@testable import KeyboardSwitcherCore

final class InkCatalogTests: XCTestCase {
    private let white = "#FAFAF7"
    private let gray = "#E9E9E5"
    private let beige = "#F5F1E8"

    func testSubstratesAndInksCarryThePublishedHexValues() {
        XCTAssertEqual(InkCatalog.substrates.map(\.hex), [white, gray, beige])
        let expected = [
            "cobalt": "#2148B8", "royalBlue": "#2058D4", "botanicalGreen": "#008A4B", "mintGreen": "#5EB783",
            "terracotta": "#C65F38", "signalRed": "#C83232", "aubergine": "#63365F", "charcoal": "#30343A",
            "powderBlue": "#9EB8D3", "oxblood": "#8F3434", "electricBlue": "#173AE3", "carbon": "#242321",
            "warmCharcoal": "#302D2E", "ultramarine": "#263E99", "safetyOrange": "#E55D2B", "cyan": "#159DDA",
            "brickRed": "#B64032", "tangerine": "#E46C2D", "slateBlue": "#4773A5",
        ]
        XCTAssertEqual(InkCatalog.inks.count, 19)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: InkCatalog.inks.map { ($0.id, $0.hex) }), expected)
        XCTAssertEqual(InkCatalog.ink("cobalt")?.name, "Cobalt")
        XCTAssertEqual(InkCatalog.substrate("beige")?.hex, beige)
        XCTAssertNil(InkCatalog.ink("magenta"))
    }

    func testEveryPairNamesTwoCatalogInks() {
        XCTAssertEqual(InkCatalog.pairs.count, 6)
        for pair in InkCatalog.pairs {
            XCTAssertEqual(pair.inkIDs.compactMap(InkCatalog.ink).count, 2, pair.id)
        }
    }

    func testContrastFollowsWCAGAndRejectsMalformedHex() throws {
        XCTAssertEqual(try XCTUnwrap(InkLegibility.contrast("#000000", "#FFFFFF")), 21, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(InkLegibility.contrast("ffffff", "#FFFFFF")), 1, accuracy: 0.0001)
        XCTAssertNil(InkLegibility.contrast("#12345", "#FFFFFF"))
        XCTAssertNil(InkLegibility.contrast("#000000", "#GGGGGG"))
    }

    func testTextInksPerSubstrate() {
        XCTAssertEqual(InkLegibility.textInks(on: white).count, 12)
        XCTAssertEqual(InkLegibility.textInks(on: gray).count, 10)
        XCTAssertEqual(InkLegibility.textInks(on: beige).count, 11)
        XCTAssertFalse(InkLegibility.textInks(on: white).contains { $0.id == "terracotta" })
        XCTAssertTrue(InkLegibility.tileInks(on: white).contains { $0.id == "terracotta" })
        XCTAssertTrue(InkLegibility.textInks(on: "not a colour").isEmpty)
    }

    func testPairAssignmentGivesTheTextJobToTheMoreLegibleInk() throws {
        func passing(on substrate: String) -> [String] {
            InkCatalog.pairs.filter { InkLegibility.assignment(for: $0, on: substrate) != nil }.map(\.id)
        }
        let everywhere = ["charcoal-signalRed", "cobalt-terracotta", "botanicalGreen-oxblood"]
        XCTAssertEqual(Set(passing(on: white)), Set(everywhere + ["ultramarine-safetyOrange"]))
        XCTAssertEqual(Set(passing(on: gray)), Set(everywhere))
        XCTAssertEqual(Set(passing(on: beige)), Set(everywhere + ["ultramarine-safetyOrange"]))

        let jobs = try XCTUnwrap(InkLegibility.assignment(for: InkCatalog.pairs[3], on: white))
        XCTAssertEqual(jobs.textInk.id, "oxblood")
        XCTAssertEqual(jobs.tileInk.id, "botanicalGreen")
        XCTAssertNil(InkLegibility.assignment(for: InkPair(id: "x", inkIDs: ["cobalt", "unknown"]), on: white))
    }
}
