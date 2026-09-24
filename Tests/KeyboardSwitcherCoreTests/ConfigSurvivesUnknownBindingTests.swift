import XCTest
@testable import KeyboardSwitcherCore

/// A config written by a newer CmdIME must not cost an older one everything.
///
/// Measured 2026-09-21: a 0.7.1 build met a binding naming an action it did not have, declared the
/// whole file corrupt, moved it aside and came up with defaults — and because the replacement was
/// only ever held in memory, the config file was gone from disk. The user was told nothing. This
/// is the path a downgrade takes, so it has to cost one binding, not the file.
final class ConfigSurvivesUnknownBindingTests: XCTestCase {
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
}
