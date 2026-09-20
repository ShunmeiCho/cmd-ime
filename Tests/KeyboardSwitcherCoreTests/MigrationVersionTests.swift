import XCTest
@testable import KeyboardSwitcherCore

final class MigrationVersionTests: XCTestCase {
    func testMigrationRaisesOlderVersionsAndPinsTheThemeTheyWereShowing() {
        for version in [1, 2, 3, 4, 42] {
            var config = SwitcherConfig.default
            config.version = version
            config.switchIndicatorThemeID = nil
            let migrated = config.migrated()
            XCTAssertEqual(migrated.version, max(version, SwitcherConfig.currentVersion))
            var expected = config
            expected.version = max(version, SwitcherConfig.currentVersion)
            // No theme id means the default, and the default changed: a file older than
            // that keeps the theme it was showing, a current one is left alone.
            expected.switchIndicatorThemeID = version < SwitcherConfig.currentVersion
                ? BuiltInIndicatorThemes.legacyDefaultID
                : nil
            XCTAssertEqual(migrated, expected)
        }
    }

    func testLoadingFutureVersionDoesNotDowngradeOrRewriteIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        var future = SwitcherConfig.default
        future.version = SwitcherConfig.currentVersion + 1
        try store.save(future)
        let bytes = try Data(contentsOf: store.url)

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config.version, SwitcherConfig.currentVersion + 1)
        XCTAssertEqual(result.config, future)
        XCTAssertNil(result.migratedFromVersion)
        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
    }
}
