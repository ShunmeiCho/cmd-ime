import XCTest
@testable import KeyboardSwitcherCore

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigContainsThreeRoleBindings() {
        let config = SwitcherConfig.default

        let roles = Set(config.bindings.compactMap(\.action.role))

        XCTAssertEqual(roles, Set(InputRole.legacy))
    }

    func testConfigRoundTripsThroughJSON() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        let config = SwitcherConfig.default

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
    }

    func testLegacyConfigDefaultsSwitchIndicatorToVisible() throws {
        let json = """
        {
          "version": 1,
          "bindings": [],
          "inputSources": {}
        }
        """

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.showSwitchIndicator)
        XCTAssertEqual(config.switchIndicatorSize, .medium)
        XCTAssertEqual(config.switchIndicatorScale, SwitcherConfig.defaultSwitchIndicatorScale)
        XCTAssertEqual(config.switchIndicatorColorStyle, .role)
        XCTAssertEqual(config.switchIndicatorContentStyle, .iconAndText)
        XCTAssertEqual(config.switchIndicatorCustomColorHex, "#2F7CF6")
        XCTAssertEqual(config.switchIndicatorCustomRoleColorHexes, [:])
    }

    func testSwitchIndicatorCustomRoleColorsRoundTrip() throws {
        var config = SwitcherConfig.default
        config.setSwitchIndicatorCustomColorHex("#4D8CFF", for: .english)
        config.setSwitchIndicatorCustomColorHex("#2FBA5A", for: .chinese)
        config.setSwitchIndicatorCustomColorHex("#E9574F", for: .japanese)

        let data = try JSONEncoder().encode(config)
        let loaded = try JSONDecoder().decode(SwitcherConfig.self, from: data)

        XCTAssertEqual(loaded.switchIndicatorCustomColorHex(for: .english), "#4D8CFF")
        XCTAssertEqual(loaded.switchIndicatorCustomColorHex(for: .chinese), "#2FBA5A")
        XCTAssertEqual(loaded.switchIndicatorCustomColorHex(for: .japanese), "#E9574F")
    }

    func testOneShotModifierConflictIgnoresGesture() {
        var config = SwitcherConfig.default
        let trigger = KeyTrigger(
            kind: .oneShotModifier,
            keyCode: 54,
            keyName: "right-command",
            gesture: .doubleTap
        )

        XCTAssertEqual(config.oneShotModifierConflict(for: trigger, excluding: .english), .chinese)

        config.upsertSwitchBinding(trigger: trigger, role: .chinese)
        XCTAssertNil(config.oneShotModifierConflict(for: trigger, excluding: .chinese))
    }

    func testSwitchIndicatorScaleIsClampedWhenDecoding() throws {
        let json = """
        {
          "version": 1,
          "showSwitchIndicator": true,
          "switchIndicatorScale": 99,
          "bindings": [],
          "inputSources": {}
        }
        """

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.switchIndicatorScale, SwitcherConfig.maxSwitchIndicatorScale)
    }

    func testLoadOrRecoverReturnsDefaultWhenFileAbsent() throws {
        let store = ConfigStore(url: uniqueConfigURL())

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config, .default)
        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertTrue(result.isFirstRun)
        XCTAssertNil(result.migratedFromVersion)
        XCTAssertEqual(result.config.version, 2)
        XCTAssertEqual(result.config.slots, SwitchSlot.legacyDefaults)
        XCTAssertFalse(store.needsSlotsMigration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testLoadOrRecoverReturnsSavedConfig() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        try store.save(.default)

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config, .default)
        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertFalse(result.isFirstRun)
        XCTAssertNil(result.migratedFromVersion)
    }

    func testLoadOrRecoverBacksUpCorruptFileWithoutDestroyingIt() throws {
        let url = uniqueConfigURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let garbage = Data("{ not valid json".utf8)
        try garbage.write(to: url)
        let store = ConfigStore(url: url)

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config, .default)
        XCTAssertFalse(result.isFirstRun)
        XCTAssertNil(result.migratedFromVersion)
        let backupURL = try XCTUnwrap(result.recoveredBackupURL)
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("config.json.corrupt."))
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage)
        // The original corrupt file is moved aside, so a later save() cannot clobber the backup.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try store.save(.default)
        XCTAssertEqual(try Data(contentsOf: backupURL), garbage)
    }

    func testLoadOrRecoverCreatesAUniqueBackupEachTime() throws {
        let url = uniqueConfigURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let first = Data("{ first".utf8)
        let second = Data("{ second".utf8)
        let store = ConfigStore(url: url)

        try first.write(to: url)
        let firstResult = try store.loadOrRecover()
        try second.write(to: url)
        let secondResult = try store.loadOrRecover()

        let firstBackupURL = try XCTUnwrap(firstResult.recoveredBackupURL)
        let secondBackupURL = try XCTUnwrap(secondResult.recoveredBackupURL)
        XCTAssertNotEqual(firstBackupURL, secondBackupURL)
        XCTAssertEqual(try Data(contentsOf: firstBackupURL), first)
        XCTAssertEqual(try Data(contentsOf: secondBackupURL), second)
    }

    // Deliberately includes obsolete UI data and cross-language preferred IDs.
    private var legacyJSON: Data {
        Data("""
        {
          "version": 1,
          "showMenuBarIcon": false,
          "showSwitchIndicator": false,
          "switchIndicatorSize": "large",
          "switchIndicatorScale": 1.2,
          "switchIndicatorColorStyle": "custom",
          "switchIndicatorContentStyle": "textOnly",
          "switchIndicatorCustomColorHex": "#112233",
          "switchIndicatorCustomRoleColorHexes": {"chinese":"#ABCDEF"},
          "bindings": [
            {"trigger":{"kind":"oneShotModifier","keyCode":54,"keyName":"right-command","modifiers":[],"gesture":"doubleTap"},
             "action":{"type":"switchInputSource","role":"chinese"},"enabled":false},
            {"trigger":{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option"]},
             "action":{"type":"switchInputSource","role":"japanese"},"enabled":true},
            {"trigger":{"kind":"keyPress","keyCode":0,"keyName":"a","modifiers":[]},
             "action":{"type":"sendKey","output":{"kind":"keyPress","keyCode":11,"keyName":"b","modifiers":[]}},"enabled":true}
          ],
          "inputSources": {
            "english":{"preferredIDs":["com.apple.keylayout.ABC"],"languagePrefixes":["en"],"nameContains":["ABC"]},
            "chinese":{"preferredIDs":["com.apple.inputmethod.SCIM.ITABC","com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese","com.apple.keylayout.ABC"],"languagePrefixes":["zh"],"nameContains":["Pinyin","中文"]},
            "japanese":{"preferredIDs":["custom.missing"],"languagePrefixes":["ja"],"nameContains":["かな"]}
          }
        }
        """.utf8)
    }

    private func writeFixture(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func testRealLegacyShapeDecodesWithoutChangingVersionOrPreferences() throws {
        let config = try JSONDecoder().decode(SwitcherConfig.self, from: legacyJSON)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.slots, SwitchSlot.legacyDefaults)
        XCTAssertEqual(config.slots.map(\.id), InputRole.legacy)
        XCTAssertEqual(config.preference(for: .chinese).preferredIDs, [
            "com.apple.inputmethod.SCIM.ITABC",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "com.apple.keylayout.ABC",
        ])
        XCTAssertEqual(config.bindings.count, 3)
        XCTAssertFalse(config.bindings[0].enabled)
        XCTAssertEqual(config.bindings[0].trigger.gesture, .doubleTap)
        XCTAssertEqual(config.bindings[2].action.type, .sendKey)
        XCTAssertFalse(config.showSwitchIndicator)
        XCTAssertEqual(config.switchIndicatorScale, 1.2)
        XCTAssertEqual(config.switchIndicatorCustomRoleColorHexes, ["chinese": "#ABCDEF"])

        let encoded = try JSONEncoder().encode(config)
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyJSON) as? NSDictionary)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        XCTAssertEqual(before["inputSources"] as? NSDictionary, after["inputSources"] as? NSDictionary)
        XCTAssertEqual(config.preference(for: .chinese).fallbackLanguage, nil)
    }

    func testLoadMigrationPreservesOriginalBytesAndAllLegacySettings() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        var expected = try JSONDecoder().decode(SwitcherConfig.self, from: legacyJSON)
        expected.version = 2

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config, expected)
        XCTAssertEqual(result.migratedFromVersion, 1)
        XCTAssertFalse(result.isFirstRun)
        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertTrue(store.needsSlotsMigration)
        XCTAssertEqual(try Data(contentsOf: store.url), legacyJSON)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
        XCTAssertEqual(try store.load().version, 1)
    }

    func testVersionTwoWithoutSlotsStillNeedsBackupButDoesNotReportOldVersion() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let data = Data(String(decoding: legacyJSON, as: UTF8.self).replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2").utf8)
        try writeFixture(data, to: store.url)
        let result = try store.loadOrRecover()
        XCTAssertNil(result.migratedFromVersion)
        XCTAssertEqual(result.config.slots, SwitchSlot.legacyDefaults)
        XCTAssertTrue(store.needsSlotsMigration)
        try store.save(result.config)
        XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), data)
    }

    func testSaveCopiesLegacyBytesOnlyOnce() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        let config = try store.loadOrRecover().config
        try store.save(config)
        XCTAssertEqual(store.legacyBackupURL, store.url.appendingPathExtension("v1.bak"))
        XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), legacyJSON)
        XCTAssertFalse(store.needsSlotsMigration)
        // Simulate an old binary dropping slots again: never replace the first backup.
        try Data("{\"version\":2,\"bindings\":[],\"inputSources\":{}}".utf8).write(to: store.url)
        try store.save(config)
        XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), legacyJSON)
        XCTAssertEqual(try store.load(), config)
    }

    func testBackupFailureLeavesLegacyFileUntouched() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        try FileManager.default.createDirectory(at: store.legacyBackupURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(.default)) { error in
            guard case ConfigStoreError.backupFailed = error else {
                return XCTFail("Expected backupFailed, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.url), legacyJSON)
        XCTAssertTrue(store.needsSlotsMigration)
    }

    func testVersionTwoRoundTripPreservesSlotOrderNamesTintsAndRawRoleStrings() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let korean = InputRole(rawValue: "korean")
        var config = SwitcherConfig.default
        config.slots = [
            SwitchSlot(id: korean, name: "My Korean", tintHex: "#123456"),
            SwitchSlot(id: .english, name: "Work", tintHex: "#FEDCBA"),
        ]
        config.bindings = [KeyBinding(
            trigger: KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
            action: .switchInputSource(korean)
        )]
        config.inputSources[korean.rawValue] = RoleInputSourcePreference(preferredIDs: ["korean.source"], fallbackLanguage: "ko")
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
        try store.save(config)
        XCTAssertFalse(store.needsSlotsMigration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        let bindings = try XCTUnwrap(json["bindings"] as? [[String: Any]])
        let action = try XCTUnwrap(bindings.first?["action"] as? [String: Any])
        XCTAssertEqual(action["role"] as? String, "korean")
        let preferences = try XCTUnwrap(json["inputSources"] as? [String: [String: Any]])
        XCTAssertNil(preferences["english"]?["fallbackLanguage"])
        XCTAssertEqual(preferences["korean"]?["fallbackLanguage"] as? String, "ko")
    }

    private var resetSources: [InputSourceInfo] {
        [InputSourceInfo(id: "korean.source", localizedName: "Korean", languages: ["ko"], isSelectCapable: true)]
    }

    func testBeforeResetBackupCopiesExactBytesWithoutWritingConfig() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)

        let backup = try XCTUnwrap(store.backUpBeforeReset())

        XCTAssertEqual(backup, store.url.appendingPathExtension("before-reset.bak"))
        XCTAssertEqual(try Data(contentsOf: backup), legacyJSON)
        XCTAssertEqual(try Data(contentsOf: store.url), legacyJSON)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
    }

    func testResetBacksUpLegacyBytesBeforeMigrationAndSavesDetectedSlotsWithGlobalSettings() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        let config = try store.loadOrRecover().config
        let original = config

        let result = try store.resettingSlots(in: config, from: resetSources)

        XCTAssertEqual(config, original)
        XCTAssertEqual(try Data(contentsOf: store.url.appendingPathExtension("before-reset.bak")), legacyJSON)
        XCTAssertEqual(try Data(contentsOf: store.legacyBackupURL), legacyJSON)
        XCTAssertEqual(try store.load(), result)
        let detected = SwitcherConfig.detected(from: resetSources)
        XCTAssertEqual(result.slots, detected.slots)
        XCTAssertEqual(result.bindings, detected.bindings)
        XCTAssertEqual(result.inputSources, detected.inputSources)
        XCTAssertEqual(result.switchIndicatorCustomRoleColorHexes, [:])
        XCTAssertEqual(result.showSwitchIndicator, config.showSwitchIndicator)
        XCTAssertEqual(result.switchIndicatorSize, config.switchIndicatorSize)
        XCTAssertEqual(result.switchIndicatorScale, config.switchIndicatorScale)
        XCTAssertEqual(result.switchIndicatorColorStyle, config.switchIndicatorColorStyle)
        XCTAssertEqual(result.switchIndicatorContentStyle, config.switchIndicatorContentStyle)
        XCTAssertEqual(result.switchIndicatorCustomColorHex, config.switchIndicatorCustomColorHex)
    }

    func testRepeatedResetsPreserveEveryPreResetFile() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try store.save(.default)
        let firstBytes = try Data(contentsOf: store.url)
        let first = try store.resettingSlots(in: .default, from: resetSources)
        let secondBytes = try Data(contentsOf: store.url)
        XCTAssertNotEqual(firstBytes, secondBytes)

        _ = try store.resettingSlots(in: first, from: [])

        let canonical = store.url.appendingPathExtension("before-reset.bak")
        XCTAssertEqual(try Data(contentsOf: canonical), firstBytes)
        let backups = try FileManager.default.contentsOfDirectory(at: store.url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.json.before-reset.") && $0.lastPathComponent != canonical.lastPathComponent }
        XCTAssertEqual(backups.count, 1)
        let secondBackup = try XCTUnwrap(backups.first)
        let uuid = secondBackup.lastPathComponent
            .replacingOccurrences(of: "config.json.before-reset.", with: "")
            .replacingOccurrences(of: ".bak", with: "")
        XCTAssertNotNil(UUID(uuidString: uuid))
        XCTAssertEqual(try Data(contentsOf: secondBackup), secondBytes)
    }

    func testResetBackupDirectoryFailureLeavesDiskAndInputConfigUntouched() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        let config = try store.loadOrRecover().config
        let original = config
        XCTAssertNotEqual(config.rebuildingSlots(from: resetSources), config)
        let backup = store.url.appendingPathExtension("before-reset.bak")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)

        XCTAssertThrowsError(try store.resettingSlots(in: config, from: resetSources)) { error in
            guard case let ConfigStoreError.backupFailed(url, _) = error else {
                return XCTFail("Expected backupFailed, got \(error)")
            }
            XCTAssertEqual(url, backup)
        }

        XCTAssertEqual(config, original)
        XCTAssertEqual(try Data(contentsOf: store.url), legacyJSON)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyBackupURL.path))
    }

    func testResetWithoutExistingFileCreatesNoBackup() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        XCTAssertNil(try store.backUpBeforeReset())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.deletingLastPathComponent().path))

        let result = try store.resettingSlots(in: .default, from: resetSources)

        XCTAssertEqual(result, SwitcherConfig.detected(from: resetSources))
        XCTAssertEqual(try store.load(), result)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        XCTAssertEqual(files, ["config.json"])
    }

    func testResetStillRefusesToOverwriteLegacyFileWhenMigrationBackupFails() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try writeFixture(legacyJSON, to: store.url)
        try FileManager.default.createDirectory(at: store.legacyBackupURL, withIntermediateDirectories: false)
        let config = try store.loadOrRecover().config

        XCTAssertThrowsError(try store.resettingSlots(in: config, from: resetSources)) { error in
            guard case let ConfigStoreError.backupFailed(url, _) = error else {
                return XCTFail("Expected backupFailed, got \(error)")
            }
            XCTAssertEqual(url, store.legacyBackupURL)
        }

        XCTAssertEqual(try Data(contentsOf: store.url), legacyJSON)
        XCTAssertEqual(try Data(contentsOf: store.url.appendingPathExtension("before-reset.bak")), legacyJSON)
    }

    private func uniqueConfigURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    func testUpsertSwitchBindingReplacesExistingRoleBinding() {
        var config = SwitcherConfig.default
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option")

        config.upsertSwitchBinding(trigger: trigger, role: .japanese)

        let japaneseBindings = config.bindings.filter { binding in
            binding.action.type == .switchInputSource && binding.action.role == .japanese
        }

        XCTAssertEqual(japaneseBindings.map(\.trigger), [trigger])
    }

    func testSanitizePreferredIDsRemovesCrossRoleSelectableSources() {
        var config = SwitcherConfig.default
        config.inputSources[InputRole.english.rawValue]?.preferredIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "custom.missing",
        ]
        config.inputSources[InputRole.chinese.rawValue]?.preferredIDs = [
            "com.apple.inputmethod.SCIM.ITABC",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "com.apple.keylayout.ABC",
            "com.apple.inputmethod.SCIM",
        ]
        let sources = [
            InputSourceInfo(
                id: "com.apple.keylayout.ABC",
                localizedName: "ABC",
                languages: ["en"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.SCIM.ITABC",
                localizedName: "Pinyin - Simplified",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.SCIM",
                localizedName: "Chinese, Simplified",
                languages: ["zh-Hans"],
                isSelectCapable: false
            ),
        ]

        config.sanitizePreferredIDs(using: sources)

        XCTAssertEqual(
            config.preference(for: .english).preferredIDs,
            [
                "com.apple.keylayout.ABC",
                "custom.missing",
            ]
        )
        XCTAssertEqual(
            config.preference(for: .chinese).preferredIDs,
            [
                "com.apple.inputmethod.SCIM.ITABC",
                "com.apple.inputmethod.SCIM",
            ]
        )
    }

    func testSanitizePreferredIDsPreventsCrossRoleBestMatchWhenPrimaryIsMissing() {
        var config = SwitcherConfig.default
        config.inputSources[InputRole.chinese.rawValue]?.preferredIDs = [
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "com.apple.keylayout.ABC",
        ]
        let sources = [
            InputSourceInfo(
                id: "com.apple.keylayout.ABC",
                localizedName: "ABC",
                languages: ["en"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        config.sanitizePreferredIDs(using: sources)
        let match = InputSourceMatcher.bestMatch(for: .chinese, sources: sources, config: config)

        XCTAssertNil(match)
    }
}
