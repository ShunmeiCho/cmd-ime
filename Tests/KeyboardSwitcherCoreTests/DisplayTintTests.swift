import XCTest
@testable import KeyboardSwitcherCore

final class DisplayTintTests: XCTestCase {
    private let surfaces = ["#18181C", "#1E1E22", "#F2F2F4", "#FAFAF7", "#E9E9E5", "#F5F1E8"]
    private let extremes = ["#000000", "#FFFFFF", "#FFF59D", "#101014", "#0A1E5C"]

    func testPassingColourIsReturnedUnchanged() {
        XCTAssertEqual(DisplayTint.adjusted("#4d8cff", against: "#18181C", minimum: 3.0), "#4D8CFF")
        XCTAssertEqual(DisplayTint.adjusted("#242321", against: "#FAFAF7", minimum: 4.5), "#242321")
    }

    func testEveryAssignableColourReachesTheMinimumOnEverySurface() throws {
        for surface in surfaces {
            for hex in SlotPalette.colors + extremes {
                for minimum in [3.0, 4.5] {
                    let tint = try XCTUnwrap(DisplayTint.adjusted(hex, against: surface, minimum: minimum))
                    let ratio = try XCTUnwrap(InkLegibility.contrast(tint, surface))
                    XCTAssertGreaterThanOrEqual(ratio, minimum, "\(hex) on \(surface)")
                }
            }
        }
    }

    func testAdjustmentKeepsTheHueOfChromaticColours() throws {
        for (hex, surface) in [("#0A1E5C", "#18181C"), ("#E49B35", "#FAFAF7"), ("#33A854", "#E9E9E5")] {
            let tint = try XCTUnwrap(DisplayTint.adjusted(hex, against: surface, minimum: 4.5))
            XCTAssertNotEqual(tint, hex)
            let before = try XCTUnwrap(IndicatorRGB(hex: hex)).hsl.hue
            let after = try XCTUnwrap(IndicatorRGB(hex: tint)).hsl.hue
            let distance = min(abs(before - after), 360 - abs(before - after))
            XCTAssertLessThanOrEqual(distance, 2, "\(hex) became \(tint)")
        }
    }

    func testTileKeepsAWhiteGlyphAndDeepensOnlyPaleFills() throws {
        for hex in SlotPalette.colors {
            let tile = try XCTUnwrap(DisplayTint.tile(fillHex: hex))
            XCTAssertEqual(tile.glyphHex, "#FFFFFF", hex)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(tile.fillHex, "#FFFFFF")), 3.0, hex)
            let isDeepened = ["#E49B35", "#32A6A8"].contains(hex)
            XCTAssertEqual(tile.fillHex != hex, isDeepened, hex)
        }
    }

    func testTileFallsBackToTheDarkGlyphOnTheStoredFill() throws {
        for hex in ["#FFFFFF", "#FFF59D"] {
            let tile = try XCTUnwrap(DisplayTint.tile(fillHex: hex))
            XCTAssertEqual(tile.fillHex, hex)
            XCTAssertEqual(tile.glyphHex, DisplayTint.darkGlyphHex)
        }
    }

    func testMalformedHexReturnsNil() {
        XCTAssertNil(DisplayTint.adjusted("blue", against: "#FFFFFF", minimum: 3))
        XCTAssertNil(DisplayTint.adjusted("#4D8CFF", against: "#FFF", minimum: 3))
        XCTAssertNil(DisplayTint.tile(fillHex: "#12"))
    }

    func testDensityStopsAtTheFloorAndNeverThinsAnIllegibleInk() {
        XCTAssertEqual(DisplayTint.density(of: "#242321", on: "#FAFAF7"), 0.72, accuracy: 0.0001)
        XCTAssertEqual(DisplayTint.density(of: "#2148B8", on: "#FAFAF7"), 0.78, accuracy: 0.0001)
        XCTAssertEqual(DisplayTint.density(of: "#2148B8", on: "#F5F1E8"), 0.80, accuracy: 0.0001)
        XCTAssertEqual(DisplayTint.density(of: "#C65F38", on: "#FAFAF7"), 1, accuracy: 0.0001)
        for ink in InkCatalog.inks {
            XCTAssertGreaterThanOrEqual(DisplayTint.density(of: ink.hex, on: "#E9E9E5"), 0.72)
        }
    }
}
