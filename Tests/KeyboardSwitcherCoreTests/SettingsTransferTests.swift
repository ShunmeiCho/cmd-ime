import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct SettingsTransferTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// A settings directory the way the app leaves it: config, one theme, one font, recipes.
    private func makeTransfer(named name: String, config: SwitcherConfig = .default) throws -> SettingsTransfer {
        let directory = root.appendingPathComponent(name)
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        try store.save(config)
        try FileManager.default.createDirectory(at: store.themesDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.fontsDirectoryURL, withIntermediateDirectories: true)
        try Data("{\"theme\": \"\(name)\"}".utf8).write(to: store.themesDirectoryURL.appendingPathComponent("Mine.json"))
        try Data("font-\(name)".utf8).write(to: store.fontsDirectoryURL.appendingPathComponent("Face.otf"))
        let recipesURL = directory.appendingPathComponent("activation-recipes.json")
        try Data("{\"recipes\": []}".utf8).write(to: recipesURL)
        return SettingsTransfer(store: store, recipesURL: recipesURL)
    }

    private func emptyTransfer(named name: String) -> SettingsTransfer {
        let directory = root.appendingPathComponent(name)
        return SettingsTransfer(
            store: ConfigStore(url: directory.appendingPathComponent("config.json")),
            recipesURL: directory.appendingPathComponent("activation-recipes.json")
        )
    }

    @Test("an export holds the config, themes, fonts and recipes")
    func exportCopiesEverything() throws {
        let transfer = try makeTransfer(named: "source")
        let destination = root.appendingPathComponent("export")

        let plan = try transfer.export(to: destination)

        #expect(plan.themeFileNames == ["Mine.json"])
        #expect(plan.fontFileNames == ["Face.otf"])
        #expect(plan.includesActivationRecipes)
        #expect(try Data(contentsOf: destination.appendingPathComponent("config.json"))
            == Data(contentsOf: transfer.store.url))
    }

    @Test("an export never writes into an existing path")
    func exportRefusesExistingDestination() throws {
        let transfer = try makeTransfer(named: "source")
        let destination = root.appendingPathComponent("taken")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        #expect(throws: SettingsTransferError.destinationExists(destination.path)) {
            try transfer.export(to: destination)
        }
    }

    @Test("an import replaces the settings and keeps the old ones in a backup folder")
    func importReplacesAndBacksUp() throws {
        var exported = SwitcherConfig.default
        exported.rememberInputSourcePerApp = true
        let source = try makeTransfer(named: "source", config: exported)
        let folder = root.appendingPathComponent("export")
        _ = try source.export(to: folder)
        let target = try makeTransfer(named: "target")
        let before = try Data(contentsOf: target.store.url)

        let result = try target.importSettings(from: folder)

        #expect(try target.store.load().rememberInputSourcePerApp)
        #expect(result.config == (try target.store.load()))
        #expect(try String(decoding: Data(contentsOf: target.store.themesDirectoryURL
            .appendingPathComponent("Mine.json")), as: UTF8.self).contains("source"))
        let backup = try #require(result.backupURL)
        #expect(backup.path.contains("/backups/before-import-"))
        #expect(try Data(contentsOf: backup.appendingPathComponent("config.json")) == before)
        #expect(try Data(contentsOf: backup.appendingPathComponent("fonts/Face.otf")) == Data("font-target".utf8))
    }

    @Test("local files the export does not have are kept")
    func importKeepsOtherLocalFiles() throws {
        let source = try makeTransfer(named: "source")
        let folder = root.appendingPathComponent("export")
        _ = try source.export(to: folder)
        let target = try makeTransfer(named: "target")
        let extraTheme = target.store.themesDirectoryURL.appendingPathComponent("Other.json")
        try Data("{}".utf8).write(to: extraTheme)

        _ = try target.importSettings(from: folder)

        #expect(FileManager.default.fileExists(atPath: extraTheme.path))
    }

    @Test("settings from a newer CmdIME are refused and nothing changes")
    func importRefusesNewerVersion() throws {
        let folder = root.appendingPathComponent("newer")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newer = SwitcherConfig.currentVersion + 1
        try Data(#"{"version": \#(newer), "bindings": [], "inputSources": {}}"#.utf8)
            .write(to: folder.appendingPathComponent("config.json"))
        let target = try makeTransfer(named: "target")
        let before = try Data(contentsOf: target.store.url)

        #expect(throws: SettingsTransferError.newerVersion(found: newer, supported: SwitcherConfig.currentVersion)) {
            try target.importSettings(from: folder)
        }
        #expect(try Data(contentsOf: target.store.url) == before)
        #expect(!FileManager.default.fileExists(
            atPath: target.store.url.deletingLastPathComponent().appendingPathComponent("backups").path
        ))
    }

    @Test("a folder with no config.json or an unreadable one is refused")
    func importRefusesBadFolders() throws {
        let target = emptyTransfer(named: "target")
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: SettingsTransferError.notAnExport(empty.path)) {
            try target.inspect(empty)
        }

        try Data("not json".utf8).write(to: empty.appendingPathComponent("config.json"))
        #expect {
            try target.inspect(empty)
        } throws: { error in
            if case .unreadableConfig = error as? SettingsTransferError { return true }
            return false
        }
    }

    @Test("an import into a fresh Mac needs no backup and does not bring back the setup guide")
    func importIntoEmptySettings() throws {
        var exported = SwitcherConfig.default
        exported.hasCompletedSetup = false
        let source = try makeTransfer(named: "source", config: exported)
        let folder = root.appendingPathComponent("export")
        _ = try source.export(to: folder)
        let target = emptyTransfer(named: "target")

        let result = try target.importSettings(from: folder)

        #expect(result.backupURL == nil)
        #expect(try target.store.load().hasCompletedSetup)
        #expect(FileManager.default.fileExists(atPath: target.recipesURL.path))
    }
}
