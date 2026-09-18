import XCTest
@testable import KeyboardSwitcherCore

final class PartialConfigDecodingTests: XCTestCase {
    func testSlotWithOnlyIDGetsStableNameAndPaletteTint() throws {
        let slot = try JSONDecoder().decode(SwitchSlot.self, from: Data(#"{"id":"korean"}"#.utf8))
        XCTAssertEqual(slot.id.rawValue, "korean")
        XCTAssertEqual(slot.name, "korean")
        XCTAssertEqual(slot.tintHex, SlotPalette.nextColor(for: slot.id, used: []))
        let legacy = try JSONDecoder().decode(SwitchSlot.self, from: Data(#"{"id":"chinese"}"#.utf8))
        XCTAssertEqual(legacy.name, "Chinese")
        XCTAssertEqual(legacy.tintHex, "#33A854")
    }

    func testPartialSlotKeepsExplicitNameAndTint() throws {
        let named = try JSONDecoder().decode(SwitchSlot.self, from: Data(#"{"id":"korean","name":"Work"}"#.utf8))
        XCTAssertEqual(named.name, "Work")
        XCTAssertEqual(named.tintHex, SlotPalette.colors[0])
        let tinted = try JSONDecoder().decode(SwitchSlot.self, from: Data(##"{"id":"korean","tintHex":"#123456"}"##.utf8))
        XCTAssertEqual(tinted.name, "korean")
        XCTAssertEqual(tinted.tintHex, "#123456")
    }

    func testNewPreferenceDefaultsUnusedArraysToEmpty() throws {
        let preference = try JSONDecoder().decode(RoleInputSourcePreference.self, from: Data(#"{"preferredIDs":["ko.source"],"fallbackLanguage":"ko"}"#.utf8))
        XCTAssertEqual(preference, RoleInputSourcePreference(preferredIDs: ["ko.source"], fallbackLanguage: "ko"))
        let empty = try JSONDecoder().decode(RoleInputSourcePreference.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, RoleInputSourcePreference())
        let legacy = try JSONDecoder().decode(RoleInputSourcePreference.self, from: Data(#"{"languagePrefixes":["zh"],"nameContains":["Pinyin"]}"#.utf8))
        XCTAssertEqual(legacy.preferredIDs, [])
        XCTAssertEqual(legacy.languagePrefixes, ["zh"])
        XCTAssertEqual(legacy.nameContains, ["Pinyin"])
        XCTAssertNil(legacy.fallbackLanguage)
    }

    func testPartialConfigLoadsWithoutRecoveryOrDiskChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        let data = Data(#"{"version":2,"slots":[{"id":"korean"}],"bindings":[],"inputSources":{"korean":{"preferredIDs":["ko.source"],"fallbackLanguage":"ko"}}}"#.utf8)
        try data.write(to: store.url)

        let result = try store.loadOrRecover()

        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertFalse(result.isFirstRun)
        XCTAssertEqual(result.config.slots.map(\.id.rawValue), ["korean"])
        XCTAssertEqual(result.config.preference(for: InputRole(rawValue: "korean")).preferredIDs, ["ko.source"])
        XCTAssertEqual(try Data(contentsOf: store.url), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["config.json"])
        let roundTrip = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(result.config))
        XCTAssertEqual(roundTrip, result.config)
    }

    func testDefaultsDoNotHideMissingIDsOrInvalidFieldTypes() {
        XCTAssertThrowsError(try JSONDecoder().decode(SwitchSlot.self, from: Data(#"{"name":"Missing ID"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SwitchSlot.self, from: Data(#"{"id":"korean","name":3}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RoleInputSourcePreference.self, from: Data(#"{"preferredIDs":"ko.source"}"#.utf8)))
    }
}
