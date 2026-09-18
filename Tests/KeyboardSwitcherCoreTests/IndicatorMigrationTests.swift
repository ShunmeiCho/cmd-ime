import XCTest
@testable import KeyboardSwitcherCore

final class IndicatorMigrationTests: XCTestCase {
    private func customConfig(_ hexes: [String: String]) -> SwitcherConfig {
        var config = SwitcherConfig.default
        config.switchIndicatorColorStyle = .custom
        config.switchIndicatorCustomColorHex = "#123456"
        config.switchIndicatorCustomRoleColorHexes = hexes
        return config
    }

    func testCustomColoursMoveIntoSlotTints() {
        let migrated = customConfig(["english": "ff8800", "japanese": " #0a1e5c "]).migrated()

        XCTAssertEqual(migrated.slot(.english)?.tintHex, "#FF8800")
        XCTAssertEqual(migrated.slot(.japanese)?.tintHex, "#0A1E5C")
        XCTAssertEqual(migrated.slot(.chinese)?.tintHex, "#33A854")
        XCTAssertEqual(migrated.switchIndicatorColorStyle, .role)
        XCTAssertEqual(migrated.switchIndicatorCustomRoleColorHexes, [:])
        XCTAssertEqual(migrated.switchIndicatorCustomColorHex, "#123456")
    }

    func testMissingSlotsAndInvalidHexAreIgnored() {
        let migrated = customConfig(["korean": "#FF8800", "english": "orange"]).migrated()

        XCTAssertEqual(migrated.slots, SwitcherConfig.default.slots)
        XCTAssertEqual(migrated.switchIndicatorColorStyle, .role)
        XCTAssertEqual(migrated.switchIndicatorCustomRoleColorHexes, [:])
    }

    func testOtherStylesAreLeftUntouched() {
        for style in SwitchIndicatorColorStyle.selectable {
            var config = customConfig(["english": "#FF8800"])
            config.switchIndicatorColorStyle = style
            XCTAssertEqual(config.migrated(), config)
        }
        XCTAssertEqual(SwitchIndicatorColorStyle.selectable, [.role, .accent, .monochrome])
    }

    func testMigratedConfigSurvivesASaveAndLoadWithoutABackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        try store.save(customConfig(["english": "#FF8800"]))

        let loaded = try store.loadOrRecover()
        XCTAssertNil(loaded.migratedFromVersion)
        XCTAssertNil(try store.save(loaded.config))

        let reloaded = try store.loadOrRecover().config
        XCTAssertEqual(reloaded, loaded.config)
        XCTAssertEqual(reloaded.slot(.english)?.tintHex, "#FF8800")
        let json = String(decoding: try Data(contentsOf: store.url), as: UTF8.self)
        XCTAssertTrue(json.contains(#""switchIndicatorColorStyle" : "role""#))
        XCTAssertTrue(json.contains(#""switchIndicatorCustomRoleColorHexes" : {"#))
    }

    func testFilesWithoutTheNewKeysDecodeWithNilThemeAndSymbol() throws {
        let encoded = try JSONEncoder().encode(SwitcherConfig.default)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("switchIndicatorThemeID"))
        XCTAssertFalse(text.contains("symbol"))

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: encoded)
        XCTAssertNil(decoded.switchIndicatorThemeID)
        XCTAssertTrue(decoded.slots.allSatisfy { $0.symbol == nil })
        XCTAssertEqual(decoded.version, SwitcherConfig.currentVersion)
    }

    func testThemeIDRoundTripsEvenWhenUnknown() throws {
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = "a-theme-that-was-deleted"
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }
}
