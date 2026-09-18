import XCTest
@testable import KeyboardSwitcherCore

final class MigrationVersionTests: XCTestCase {
    func testMigrationOnlyRaisesOlderVersions() {
        for version in [1, 2, 3, 42] {
            var config = SwitcherConfig.default
            config.version = version
            let migrated = config.migrated()
            XCTAssertEqual(migrated.version, max(version, SwitcherConfig.currentVersion))
            var expected = config
            expected.version = max(version, SwitcherConfig.currentVersion)
            XCTAssertEqual(migrated, expected)
        }
    }

    func testLoadingFutureVersionDoesNotDowngradeOrRewriteIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        var future = SwitcherConfig.default
        future.version = 3
        try store.save(future)
        let bytes = try Data(contentsOf: store.url)

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config.version, 3)
        XCTAssertEqual(result.config, future)
        XCTAssertNil(result.migratedFromVersion)
        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
    }
}
