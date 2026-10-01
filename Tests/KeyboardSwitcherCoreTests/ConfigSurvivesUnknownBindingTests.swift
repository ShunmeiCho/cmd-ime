import XCTest
@testable import KeyboardSwitcherCore

/// A config written by a newer CmdIME must not cost an older one everything.
///
/// Measured 2026-09-21: a 0.7.1 build met a binding naming an action it did not have, declared the
/// whole file corrupt, moved it aside and came up with defaults — and because the replacement was
/// only ever held in memory, the config file was gone from disk. The user was told nothing. This
/// is the path a downgrade takes, so it has to cost one binding, not the file.
final class ConfigSurvivesUnknownBindingTests: XCTestCase {
    func testConfigWithoutModifierSidesDecodesAsEitherSide() throws {
        let json = """
        {"version":2,"bindings":[
          {"trigger":{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option"],"gesture":"tap"},
           "action":{"type":"switchInputSource","role":"japanese"},"enabled":true}
        ],"inputSources":{}}
        """
        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.bindings.count, 1)
        XCTAssertEqual(config.bindings.first?.trigger, try ShortcutParser.parse("option+j"))
        XCTAssertEqual(config.unreadableBindingCount, 0)
    }

    func testEmptyModifierSidesAreOmittedWithoutChangingLegacyTriggerBytes() throws {
        let json = #"{"gesture":"tap","keyCode":38,"keyName":"j","kind":"keyPress","modifiers":["shift","option"]}"#
        let trigger = try JSONDecoder().decode(KeyTrigger.self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(trigger), Data(json.utf8))
    }

    func testModifierSidesEncodeAsRawValueKeyedObject() throws {
        let json = #"{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option"],"modifierSides":{"option":"left"}}"#
        let trigger = try JSONDecoder().decode(KeyTrigger.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(trigger)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["modifierSides"] as? [String: String], ["option": "left"])
        XCTAssertEqual(try JSONDecoder().decode(KeyTrigger.self, from: encoded), trigger)
    }

    func testUnreadableSideValuesKeepBindingAndOtherValidSides() throws {
        for invalid in [#""future-side""#, "42", "null", "[]", "{}"] {
            let json = """
            {"version":2,"bindings":[
              {"trigger":{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option","shift"],
                          "modifierSides":{"option":\(invalid),"shift":"right"}},
               "action":{"type":"switchInputSource","role":"japanese"},"enabled":true}
            ],"inputSources":{}}
            """
            let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
            XCTAssertEqual(config.bindings.count, 1)
            XCTAssertEqual(config.unreadableBindingCount, 0)
            XCTAssertEqual(config.bindings.first?.trigger.displayName, "option+right-shift+j")
        }
    }

    func testDecodingDropsUnknownAndInapplicableModifierSides() throws {
        let json = #"{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option","fn","capsLock"],"modifierSides":{"option":"right","control":"left","fn":"left","capsLock":"right","future":"left"}}"#
        let trigger = try JSONDecoder().decode(KeyTrigger.self, from: Data(json.utf8))
        XCTAssertEqual(trigger.modifierSides, [.option: .right])
        let oneShotJSON = #"{"kind":"oneShotModifier","keyCode":55,"keyName":"left-command","modifiers":["command"],"modifierSides":{"command":"left"}}"#
        let oneShot = try JSONDecoder().decode(KeyTrigger.self, from: Data(oneShotJSON.utf8))
        XCTAssertTrue(oneShot.modifierSides.isEmpty)
    }

    func testUnreadableModifierSidesContainerKeepsBinding() throws {
        for invalid in ["42", "null", "[]", #""invalid""#] {
            let json = """
            {"version":2,"bindings":[
              {"trigger":{"kind":"keyPress","keyCode":38,"keyName":"j","modifiers":["option"],"modifierSides":\(invalid)},
               "action":{"type":"switchInputSource","role":"japanese"},"enabled":true}
            ],"inputSources":{}}
            """
            let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
            XCTAssertEqual(config.bindings.count, 1)
            XCTAssertEqual(config.unreadableBindingCount, 0)
            XCTAssertEqual(config.bindings.first?.trigger, try ShortcutParser.parse("option+j"))
        }
    }

    private func makeStore() throws -> (ConfigStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        return (ConfigStore(url: url), url)
    }

    private func write(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url)
    }

    /// The exact shape that lost the file: a real binding beside one naming an unknown action.
    func testKeepsTheBindingsItUnderstandsAndCountsTheRest() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(
            """
            {"version":2,"bindings":[
              {"trigger":{"kind":"oneShotModifier","keyCode":55,"keyName":"left-command","modifiers":[],"gesture":"tap"},
               "action":{"type":"switchInputSource","role":"english"},"enabled":true},
              {"trigger":{"kind":"oneShotModifier","keyCode":60,"keyName":"right-shift","modifiers":[],"gesture":"tap"},
               "action":{"type":"summonADragon","role":"chinese"},"enabled":true}
            ],"inputSources":{}}
            """,
            to: url
        )

        let result = try store.loadOrRecover()

        XCTAssertNil(result.recoveredBackupURL, "one unreadable binding is not a corrupt file")
        XCTAssertEqual(result.config.bindings.count, 1)
        XCTAssertEqual(result.config.bindings.first?.action.role?.rawValue, "english")
        XCTAssertEqual(result.config.unreadableBindingCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the file must stay where it is")
    }

    func testAConfigThisBuildFullyUnderstandsIsUntouched() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(
            """
            {"version":2,"bindings":[
              {"trigger":{"kind":"oneShotModifier","keyCode":55,"keyName":"left-command","modifiers":[],"gesture":"tap"},
               "action":{"type":"switchInputSource","role":"english"},"enabled":true}
            ],"inputSources":{}}
            """,
            to: url
        )

        let result = try store.loadOrRecover()

        XCTAssertEqual(result.config.bindings.count, 1)
        XCTAssertEqual(result.config.unreadableBindingCount, 0)
        XCTAssertNil(result.recoveredBackupURL)
    }

    /// Truly unreadable bytes still go aside — but a working config has to land back on disk.
    func testRecoveryLeavesAUsableConfigOnDisk() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write("this is not json at all", to: url)

        let result = try store.loadOrRecover()

        XCTAssertNotNil(result.recoveredBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "a config must exist after recovery")
        XCTAssertNoThrow(try store.load(), "and it must be readable")
    }

    /// Pinyin recovery was removed after 0.8.3. A config that still binds it loses that binding
    /// and nothing else, which is what the 0.8.3 release notes promised.
    func testARemovedRecoveryBindingIsDroppedAlone() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(
            """
            {"version":2,"bindings":[
              {"trigger":{"kind":"oneShotModifier","keyCode":55,"keyName":"left-command","modifiers":[],"gesture":"tap"},
               "action":{"type":"switchInputSource","role":"english"},"enabled":true},
              {"trigger":{"kind":"keyPress","keyCode":15,"keyName":"r","modifiers":["control","option"],"gesture":"tap"},
               "action":{"type":"recoverPinyin","role":"chinese"},"enabled":true}
            ],"inputSources":{}}
            """,
            to: url
        )

        let result = try store.loadOrRecover()

        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertEqual(result.config.bindings.map(\.action.role), [InputRole(rawValue: "english")])
        XCTAssertEqual(result.config.unreadableBindingCount, 1)
    }

    /// A build from before peek existed has no `showIndicator` case, so to it the action is an
    /// unknown name. This writes the peek binding exactly as this build does, renames only the
    /// action to one no build knows, and checks the older build's view: one binding lost, not the file.
    func testAPeekBindingCostsAnOlderBuildOnlyThatBinding() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let config = try SwitcherConfig.default.replacingPeekBinding(with: ShortcutParser.parse("option+p"))
        let written = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertTrue(written.contains(#""type":"showIndicator""#))
        try write(written.replacingOccurrences(of: #""type":"showIndicator""#, with: #""type":"notInThisBuild""#), to: url)

        let result = try store.loadOrRecover()

        XCTAssertNil(result.recoveredBackupURL)
        XCTAssertEqual(result.config.bindings, SwitcherConfig.default.bindings)
        XCTAssertEqual(result.config.unreadableBindingCount, 1)
    }
}
