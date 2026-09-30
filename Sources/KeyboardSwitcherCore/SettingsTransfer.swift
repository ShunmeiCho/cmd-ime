import Foundation

public enum SettingsTransferError: Error, Equatable, LocalizedError {
    case destinationExists(String)
    case nothingToExport
    case unreadableCurrentConfig(String)
    case notAnExport(String)
    case newerVersion(found: Int, supported: Int)
    case unreadableConfig(String)
    case importFailed(backup: String?, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .destinationExists(path):
            "\(path) already exists. Choose a new name; nothing is ever written over."
        case .nothingToExport:
            "There are no settings to export yet."
        case let .unreadableCurrentConfig(reason):
            "The current config.json cannot be read, so it was not exported: \(reason)"
        case let .notAnExport(path):
            "\(path) is not an exported CmdIME settings folder: it has no config.json."
        case let .newerVersion(found, supported):
            "These settings come from a newer CmdIME (config version \(found); this one reads up to \(supported)). "
                + "Update CmdIME, then import them."
        case let .unreadableConfig(reason):
            "The config.json in this folder cannot be read: \(reason)"
        case let .importFailed(backup, reason):
            "Import stopped partway: \(reason)"
                + (backup.map { " Your previous settings are in \($0)." } ?? "")
        }
    }
}

/// What an exported folder holds, read before anything is changed.
public struct SettingsImportPlan: Equatable, Sendable {
    public let config: SwitcherConfig
    public let themeFileNames: [String]
    public let fontFileNames: [String]
    public let includesActivationRecipes: Bool
}

public struct SettingsImportResult: Equatable, Sendable {
    /// The settings now on disk, which the running app should make live.
    public let config: SwitcherConfig
    /// Where the settings from before the import were copied; nil when there were none.
    public let backupURL: URL?
    public let plan: SettingsImportPlan
}

/// Exports the user's settings to a folder and imports such a folder: config.json, the
/// user themes in themes/, the imported fonts in fonts/ and the hand-edited
/// activation-recipes.json. An export never writes over anything. An import refuses
/// settings from a newer CmdIME and copies the current ones aside before it changes
/// anything; files in the export replace same-named ones, and other local files stay.
public struct SettingsTransfer {
    public static let configFileName = "config.json"
    public static let themesFolderName = "themes"
    public static let fontsFolderName = "fonts"
    public static let recipesFileName = "activation-recipes.json"
    public static let backupsFolderName = "backups"

    public let store: ConfigStore
    public let recipesURL: URL

    public init(store: ConfigStore = ConfigStore(), recipesURL: URL = ActivationRecipeStore.defaultURL) {
        self.store = store
        self.recipesURL = recipesURL
    }

    // MARK: - Export

    /// Creates `destination` as a new folder holding the settings.
    public func export(to destination: URL) throws -> SettingsImportPlan {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw SettingsTransferError.destinationExists(destination.path)
        }
        guard fileManager.fileExists(atPath: store.url.path) else { throw SettingsTransferError.nothingToExport }
        do {
            _ = try store.load()
        } catch {
            throw SettingsTransferError.unreadableCurrentConfig(error.localizedDescription)
        }
        try copyCurrentSettings(to: destination)
        return try inspect(destination)
    }

    /// Copies whatever is there, readable or not: also used for the backup before an import.
    private func copyCurrentSettings(to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: store.url.path) {
            try fileManager.copyItem(at: store.url, to: destination.appendingPathComponent(Self.configFileName))
        }
        try copyFiles(Self.themeFiles(in: store.themesDirectoryURL),
                      into: destination.appendingPathComponent(Self.themesFolderName))
        try copyFiles(Self.fontFiles(in: store.fontsDirectoryURL),
                      into: destination.appendingPathComponent(Self.fontsFolderName))
        if Self.isRegularFile(recipesURL) {
            try fileManager.copyItem(at: recipesURL, to: destination.appendingPathComponent(Self.recipesFileName))
        }
    }

    // MARK: - Import

    /// Reads and checks an exported folder without changing anything.
    public func inspect(_ folder: URL) throws -> SettingsImportPlan {
        let configURL = folder.appendingPathComponent(Self.configFileName)
        guard Self.isRegularFile(configURL) else { throw SettingsTransferError.notAnExport(folder.path) }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw SettingsTransferError.unreadableConfig(error.localizedDescription)
        }
        // Checked before decoding: a newer file can decode here and lose what this build cannot read.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = object["version"] as? Int, version > SwitcherConfig.currentVersion {
            throw SettingsTransferError.newerVersion(found: version, supported: SwitcherConfig.currentVersion)
        }
        let config: SwitcherConfig
        do {
            config = try JSONDecoder().decode(SwitcherConfig.self, from: data)
        } catch {
            throw SettingsTransferError.unreadableConfig(error.localizedDescription)
        }
        return SettingsImportPlan(
            config: config,
            themeFileNames: Self.themeFiles(in: folder.appendingPathComponent(Self.themesFolderName))
                .map(\.lastPathComponent),
            fontFileNames: Self.fontFiles(in: folder.appendingPathComponent(Self.fontsFolderName))
                .map(\.lastPathComponent),
            includesActivationRecipes: Self.isRegularFile(folder.appendingPathComponent(Self.recipesFileName))
        )
    }

    /// Checks the folder, copies the current settings into a new folder under
    /// `backups/` beside config.json, then writes the imported ones.
    public func importSettings(from folder: URL, now: Date = Date()) throws -> SettingsImportResult {
        let plan = try inspect(folder)
        let backupURL = try backUpCurrentSettings(now: now)
        do {
            // The same in-memory migration a launch applies, and never the setup guide again.
            let config = plan.config.migrated().completingSetup()
            try store.save(config)
            try replaceFiles(plan.themeFileNames, from: folder.appendingPathComponent(Self.themesFolderName),
                             into: store.themesDirectoryURL)
            try replaceFiles(plan.fontFileNames, from: folder.appendingPathComponent(Self.fontsFolderName),
                             into: store.fontsDirectoryURL)
            if plan.includesActivationRecipes {
                try Data(contentsOf: folder.appendingPathComponent(Self.recipesFileName))
                    .write(to: recipesURL, options: .atomic)
            }
            return SettingsImportResult(config: config, backupURL: backupURL, plan: plan)
        } catch {
            throw SettingsTransferError.importFailed(backup: backupURL?.path, reason: error.localizedDescription)
        }
    }

    /// Nil when there is nothing to back up (no config.json yet).
    private func backUpCurrentSettings(now: Date) throws -> URL? {
        guard FileManager.default.fileExists(atPath: store.url.path) else { return nil }
        let backups = store.url.deletingLastPathComponent().appendingPathComponent(Self.backupsFolderName)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var destination = backups.appendingPathComponent("before-import-\(formatter.string(from: now))")
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = backups.appendingPathComponent("before-import-\(formatter.string(from: now))-\(UUID().uuidString)")
        }
        do {
            try copyCurrentSettings(to: destination)
        } catch {
            throw ConfigStoreError.backupFailed(destination, underlying: error)
        }
        return destination
    }

    // MARK: - Files

    private func copyFiles(_ files: [URL], into directory: URL) throws {
        guard !files.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
    }

    private func replaceFiles(_ names: [String], from source: URL, into directory: URL) throws {
        guard !names.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data(contentsOf: source.appendingPathComponent(name))
                .write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }

    private static func themeFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.indicatorStoreFiles(in: directory, extensions: [IndicatorThemeStore.fileExtension])) ?? []
    }

    /// Oversized files are left out, as a font import in Settings would refuse them.
    private static func fontFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.indicatorStoreFiles(in: directory, extensions: FontStore.allowedExtensions)) ?? []
        return files.filter { (FileManager.default.indicatorFileSize(at: $0) ?? 0) <= FontStore.maxFileBytes }
    }

    /// A symbolic link is not followed, so an import never reads from outside the folder.
    private static func isRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }
}
