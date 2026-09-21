import XCTest
@testable import KeyboardSwitcherCore

final class IndicatorThemeTests: XCTestCase {
    private func decode(_ json: String, fileName: String = "my-theme.json") -> Result<IndicatorTheme, IndicatorThemeIssue> {
        IndicatorTheme.decoding(Data(json.utf8), fileName: fileName)
    }

    private func issue(_ json: String) -> IndicatorThemeIssue? {
        if case let .failure(issue) = decode(json) { return issue }
        return nil
    }

    func testMinimalFileTakesEveryDefault() throws {
        let theme = try decode(#"{"schemaVersion": 1, "futureKey": [1, 2]}"#).get()
        XCTAssertEqual(theme, IndicatorTheme(id: "my-theme", name: "my-theme"))
        XCTAssertEqual(theme.archetype, .tileTwoLine)
        XCTAssertEqual(theme.surface, .glass)
        XCTAssertEqual(theme.appearance, .auto)
        XCTAssertEqual(theme.colorSource, .slot)
        XCTAssertNil(theme.substrateHex)
        XCTAssertNil(theme.textInkHex)
        XCTAssertEqual([theme.cornerRadius, theme.inset, theme.strokeOpacity], [16, 9, 0.16])
        XCTAssertEqual([theme.washOpacity, theme.highlightStrength, theme.shadowStrength], [0.45, 1, 0.6])
        XCTAssertEqual(theme.typography, IndicatorTypography())
        XCTAssertFalse(theme.isBuiltIn)
    }

    func testPaperDefaultsAndNormalisedFields() throws {
        let theme = try decode(##"""
        {"schemaVersion": 1, "id": "My Theme!", "name": "  Riso  ", "surface": "paper", "tileInkHex": "c65f38"}
        """##).get()
        XCTAssertEqual(theme.id, "my-theme")
        XCTAssertEqual(theme.name, "Riso")
        XCTAssertEqual(theme.substrateHex, "#FAFAF7")
        XCTAssertEqual(theme.textInkHex, "#242321")
        XCTAssertEqual(theme.tileInkHex, "#C65F38")
    }

    func testNumbersAreClamped() throws {
        let theme = try decode("""
        {"schemaVersion": 1, "cornerRadius": 90, "tileCornerRadius": -4, "inset": 1, "strokeOpacity": 7,
         "washOpacity": 1, "highlightStrength": -1, "shadowStrength": 2, "typography": {"textScale": 9}}
        """).get()
        XCTAssertEqual([theme.cornerRadius, theme.inset, theme.strokeOpacity], [28, 4, 1])
        XCTAssertEqual(theme.tileCornerRadius, 0)
        XCTAssertEqual([theme.washOpacity, theme.highlightStrength, theme.shadowStrength], [0.9, 0, 1])
        XCTAssertEqual(theme.typography.textScale, 1.6)
        XCTAssertEqual(IndicatorTheme(id: "x", name: "x", cornerRadius: .nan).cornerRadius, 16)
        XCTAssertEqual(IndicatorTypography(textScale: .infinity).textScale, 1)
    }

    func testEachIssueHasAFailingFixture() {
        XCTAssertEqual(issue("not json"), .notJSON)
        XCTAssertEqual(issue("[1]"), .notJSON)
        XCTAssertEqual(issue(#"{"name": "No version"}"#), .unreadable("schemaVersion is missing"))
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "cornerRadius": "wide"}"#), .unreadable("cornerRadius has the wrong type"))
        XCTAssertEqual(issue(#"{"schemaVersion": 2}"#), .unsupportedSchema(2))
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "textInkHex": "blue"}"#), .invalidHex(key: "textInkHex", value: "blue"))
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "archetype": "ring"}"#), .unknownValue(key: "archetype", value: "ring"))
        XCTAssertEqual(
            issue(#"{"schemaVersion": 1, "typography": {"displayWeight": "thin"}}"#),
            .unknownValue(key: "typography.displayWeight", value: "thin")
        )
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "surface": "none"}"#), .incompatible(key: "surface", with: "archetype"))
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "id": "Builtin.glass"}"#), .reservedID("Builtin.glass"))
        XCTAssertEqual(issue(#"{"schemaVersion": 1, "id": "***"}"#), .unreadable("id is empty"))
        let oversized = Data(repeating: 32, count: IndicatorTheme.maxFileBytes + 1)
        XCTAssertEqual(IndicatorTheme.decoding(oversized, fileName: "big.json"), .failure(.unreadable("the file is larger than 64 KB")))
        XCTAssertNotNil(try? decode(#"{"schemaVersion": 1, "surface": "none", "archetype": "tileOnly"}"#).get())
        for issue in [IndicatorThemeIssue.notJSON, .duplicateID("a"), .unsupportedSchema(3)] {
            XCTAssertFalse(issue.message.isEmpty)
        }
    }

    func testRoundTripIsStable() throws {
        let theme = IndicatorTheme(
            id: "riso", name: "Riso", archetype: .stackedText, surface: .paper, colorSource: .inks,
            substrateHex: "#F5F1E8", textInkHex: "#63365F", tileCornerRadius: 4,
            typography: IndicatorTypography(displayFamily: "Futura", displayWeight: .bold, textScale: 1.25)
        )
        let data = try JSONEncoder().encode(theme)
        XCTAssertEqual(try IndicatorTheme.decoding(data, fileName: "other.json").get(), theme)
    }

    func testBuiltInsAreUniqueLegibleThemes() {
        let themes = BuiltInIndicatorThemes.all
        XCTAssertEqual(themes.count, 16)
        XCTAssertEqual(Set(themes.map(\.id)).count, 16)
        XCTAssertEqual(themes.first?.id, BuiltInIndicatorThemes.defaultID)
        for theme in themes {
            XCTAssertTrue(theme.isBuiltIn, theme.id)
            XCTAssertTrue(IndicatorThemeLegibility.issues(theme).isEmpty, theme.id)
            XCTAssertTrue(theme.surface != .none || theme.archetype == .tileOnly, theme.id)
        }
        XCTAssertEqual(themes.filter { $0.surface == .paper }.map(\.substrateHex), ["#FAFAF7", "#FAFAF7", "#E9E9E5", "#F5F1E8"])
        XCTAssertEqual(themes.first { $0.id == "builtin.paper-two-inks" }?.tileInkHex, "#C65F38")
        XCTAssertEqual(themes.first { $0.id == "builtin.typographic" }?.typography, TypographyPreset.literary.typography)
        XCTAssertEqual(TypographyPreset.programmatic.typography.utilityDesign, .monospaced)
    }

    func testLegibilityReportsAnInkThatCannotCarryText() throws {
        let theme = IndicatorTheme(id: "weak", name: "Weak", surface: .paper, colorSource: .inks,
                                   substrateHex: "#FAFAF7", textInkHex: "#C65F38", tileInkHex: "#9EB8D3")
        let issues = IndicatorThemeLegibility.issues(theme)
        XCTAssertEqual(issues.map(\.key), ["textInkHex", "tileInkHex"])
        XCTAssertEqual(issues[0].ratio, 3.94, accuracy: 0.01)
        XCTAssertEqual(issues[0].minimum, 4.5)
        XCTAssertEqual(issues[1].minimum, 3.0)
    }
}
