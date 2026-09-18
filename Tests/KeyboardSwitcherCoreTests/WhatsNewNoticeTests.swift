import XCTest
@testable import KeyboardSwitcherCore

final class WhatsNewNoticeTests: XCTestCase {
    private func shows(_ lastSeen: String?, current: String = "0.4.0", completed: Bool = true, fresh: Bool = false) -> Bool {
        WhatsNewNotice.shouldShow(lastSeen: lastSeen, current: current, hasCompletedSetup: completed, isFreshConfig: fresh)
    }

    func testOldConfigWithoutKeyLoads() throws {
        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(#"{"version":2,"bindings":[],"inputSources":{}}"#.utf8))
        XCTAssertNil(config.lastSeenWhatsNewVersion)
        XCTAssertTrue(config.hasCompletedSetup)
    }

    func testVersionRoundTripsThroughStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        var config = SwitcherConfig.default
        config.lastSeenWhatsNewVersion = "0.4.0"
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testNilVersionIsNotEncoded() throws {
        let data = try JSONEncoder().encode(SwitcherConfig.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["lastSeenWhatsNewVersion"])
    }

    func testExistingCompletedConfigWithoutSeenVersionShows() {
        XCTAssertTrue(shows(nil))
    }

    func testFreshConfigNeverShows() {
        XCTAssertFalse(shows(nil, fresh: true))
        XCTAssertFalse(shows("0.3.0", fresh: true))
    }

    func testPendingSetupNeverShows() {
        XCTAssertFalse(shows(nil, completed: false))
        XCTAssertFalse(shows("0.3.0", completed: false))
    }

    func testLowerMinorShowsNumerically() {
        XCTAssertTrue(shows("0.3.99"))
        XCTAssertTrue(shows("0.9.0", current: "0.10.0"))
    }

    func testLowerMajorShows() {
        XCTAssertTrue(shows("0.99.0", current: "1.0.0"))
    }

    func testSameMinorAndPatchUpdatesDoNotShow() {
        XCTAssertFalse(shows("0.4.0"))
        XCTAssertFalse(shows("0.4.0", current: "0.4.9"))
        XCTAssertFalse(shows("0.4.99"))
        XCTAssertFalse(shows("0.4"))
    }

    func testNewerSeenVersionDoesNotShow() {
        XCTAssertFalse(shows("0.10.0"))
        XCTAssertFalse(shows("1.0.0"))
    }

    func testMalformedVersionsDoNotShow() {
        for invalid in ["", "0", "v0.3.0", "0..3", "-1.3", "0.3.x", "0.3.0-beta", "0.3.0.1", " 0.3.0", "0.3.", "999999999999999999999999.0"] {
            XCTAssertFalse(shows(invalid), invalid)
            XCTAssertFalse(shows(nil, current: invalid), invalid)
            XCTAssertFalse(shows("0.3.0", current: invalid), invalid)
        }
    }

    func testFinishingOrSkippingSetupMarksCurrentVersionSeen() {
        let pending = SwitcherConfig.default
        let completed = pending.completingSetup(whatsNewVersion: "0.4.0")
        XCTAssertTrue(completed.hasCompletedSetup)
        XCTAssertEqual(completed.lastSeenWhatsNewVersion, "0.4.0")
        XCTAssertFalse(shows(completed.lastSeenWhatsNewVersion, completed: completed.hasCompletedSetup))
        XCTAssertNil(pending.lastSeenWhatsNewVersion)
    }

    func testClosingReopenedSetupMarksCurrentVersionSeen() {
        let existing = SwitcherConfig.default.completingSetup()
        let closed = existing.completingSetup(whatsNewVersion: "0.4.0")
        XCTAssertEqual(closed.lastSeenWhatsNewVersion, "0.4.0")
        XCTAssertFalse(shows(closed.lastSeenWhatsNewVersion))
    }
}
