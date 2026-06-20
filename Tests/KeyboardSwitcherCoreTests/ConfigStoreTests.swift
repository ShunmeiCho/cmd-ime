import XCTest
@testable import KeyboardSwitcherCore

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigContainsThreeRoleBindings() {
        let config = SwitcherConfig.default

        let roles = Set(config.bindings.compactMap(\.action.role))

        XCTAssertEqual(roles, Set(InputRole.allCases))
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

    func testLegacyConfigDefaultsMenuBarIconToVisible() throws {
        let json = """
        {
          "version": 1,
          "bindings": [],
          "inputSources": {}
        }
        """

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.showMenuBarIcon)
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
    }

    func testLoadOrRecoverReturnsSavedConfig() throws {
        let store = ConfigStore(url: uniqueConfigURL())
        try store.save(.default)

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config, .default)
        XCTAssertNil(result.recoveredBackupURL)
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
