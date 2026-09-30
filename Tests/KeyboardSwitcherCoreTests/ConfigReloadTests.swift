import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct ConfigReloadTests {
    private func encoded(_ config: SwitcherConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    @Test("the app's own save reads back as unchanged, for default and detected configs")
    func ownWriteIsUnchanged() throws {
        let sources = [
            InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
            InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin",
                            languages: ["zh-Hans"], isSelectCapable: true),
        ]
        for config in [SwitcherConfig.default, SwitcherConfig.detected(from: sources).completingSetup()] {
            #expect(ConfigReload.decide(fileData: try encoded(config), applied: config) == .unchanged)
        }
    }

    @Test("the app's own save still reads as unchanged after a binding could not be read at launch")
    func ownWriteAfterUnreadableBindingIsUnchanged() throws {
        var applied = SwitcherConfig.default
        applied.unreadableBindingCount = 1

        #expect(ConfigReload.decide(fileData: try encoded(applied), applied: applied) == .unchanged)
    }

    @Test("a change made by someone else is applied")
    func externalEditApplies() throws {
        let applied = SwitcherConfig.default
        var edited = applied
        edited.rememberInputSourcePerApp = true

        let decision = ConfigReload.decide(fileData: try encoded(edited), applied: applied)

        #expect(decision == .apply(edited))
    }

    @Test("a file an editor is halfway through writing is unreadable, and nothing is applied")
    func halfWrittenFileIsUnreadable() {
        let decision = ConfigReload.decide(fileData: Data(#"{"version": 3, "bind"#.utf8), applied: .default)

        guard case .unreadable = decision else {
            Issue.record("expected unreadable, got \(decision)")
            return
        }
    }

    @Test("a deleted file changes nothing")
    func missingFileIsUnchanged() {
        #expect(ConfigReload.decide(fileData: nil, applied: .default) == .unchanged)
    }

    @Test("an older file gets the launch migration before it is compared")
    func olderFileIsMigrated() throws {
        let json = Data(#"{"version": 2, "bindings": [], "inputSources": {}}"#.utf8)
        let expected = try JSONDecoder().decode(SwitcherConfig.self, from: json).migrated()

        #expect(ConfigReload.decide(fileData: json, applied: .default) == .apply(expected))
        #expect(ConfigReload.decide(fileData: json, applied: expected) == .unchanged)
    }

    @Test("saving over a config.json that does not decode copies it aside first")
    func saveKeepsUnreadableFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = Data(#"{"version": 3, "bind"#.utf8)
        try broken.write(to: store.url)

        try store.save(.default)

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.json.unreadable.") }
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: directory.appendingPathComponent(backup)) == broken)
        #expect(try store.load() == .default)
    }

    @Test("saving over a readable config.json leaves no extra copy")
    func saveOverReadableFileMakesNoCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        try store.save(.default)

        try store.save(.default)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["config.json"])
    }
}
