import Foundation

public struct ConfigLoadResult: Equatable, Sendable {
    public let config: SwitcherConfig
    /// Non-nil when an existing on-disk config was unreadable and got moved aside for recovery.
    public let recoveredBackupURL: URL?

    public let isFirstRun: Bool
    public let migratedFromVersion: Int?

    public init(
        config: SwitcherConfig,
        recoveredBackupURL: URL?,
        isFirstRun: Bool = false,
        migratedFromVersion: Int? = nil
    ) {
        self.config = config
        self.recoveredBackupURL = recoveredBackupURL
        self.isFirstRun = isFirstRun
        self.migratedFromVersion = migratedFromVersion
    }
}

public enum ConfigStoreError: Error, LocalizedError {
    case backupFailed(URL, underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case let .backupFailed(url, underlying):
            "Could not back up previous settings to \(url.path): \(underlying.localizedDescription)"
        }
    }
}

public struct ConfigStore {
    public var url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cmd-ime/config.json")
    }

    public var legacyBackupURL: URL {
        url.appendingPathExtension("v1.bak")
    }

    /// Based on the on-disk shape, not its version: old binaries can drop `slots`.
    public var needsSlotsMigration: Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["slots"] == nil
    }

    public func load() throws -> SwitcherConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SwitcherConfig.self, from: data)
    }

    public func loadOrDefault() throws -> SwitcherConfig {
        FileManager.default.fileExists(atPath: url.path) ? try load() : .default
    }

    /// Loads the config, but never silently destroys an existing-yet-unreadable file.
    /// - File absent: returns `.default` with no backup.
    /// - File decodes: migrates in memory only; leaves the original bytes untouched.
    /// - File present but unreadable/corrupt: moves it aside to a unique
    ///   `<name>.corrupt.<uuid>` backup,
    ///   returns `.default`, and reports the backup URL so the caller can surface it.
    public func loadOrRecover() throws -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ConfigLoadResult(config: .default, recoveredBackupURL: nil, isFirstRun: true)
        }
        do {
            let original = try load()
            return ConfigLoadResult(
                config: original.migrated(),
                recoveredBackupURL: nil,
                migratedFromVersion: original.version < SwitcherConfig.currentVersion ? original.version : nil
            )
        } catch {
            let backupURL = try backUpUnreadableFile()
            return ConfigLoadResult(config: .default, recoveredBackupURL: backupURL)
        }
    }

    private func backUpUnreadableFile() throws -> URL {
        let backupURL = url.appendingPathExtension("corrupt.\(UUID().uuidString)")
        try FileManager.default.moveItem(at: url, to: backupURL)
        return backupURL
    }

    /// Copies the current on-disk bytes before a reset, preserving all earlier backups.
    /// An absent config needs no backup; a failed backup must prevent the reset.
    public func backUpBeforeReset() throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        var backupURL = url.appendingPathExtension("before-reset.bak")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                let attributes = try fileManager.attributesOfItem(atPath: backupURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw CocoaError(.fileWriteFileExists)
                }
                repeat {
                    backupURL = url.appendingPathExtension("before-reset.\(UUID().uuidString).bak")
                } while fileManager.fileExists(atPath: backupURL.path)
            }
            try fileManager.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            throw ConfigStoreError.backupFailed(backupURL, underlying: error)
        }
    }

    /// Returns the replacement only after both backup and persistence succeed.
    public func resettingSlots(in config: SwitcherConfig, from sources: [InputSourceInfo]) throws -> SwitcherConfig {
        _ = try backUpBeforeReset()
        let replacement = config.rebuildingSlots(from: sources)
        try save(replacement)
        return replacement
    }

    public func save(_ config: SwitcherConfig) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        if needsSlotsMigration {
            var isDirectory: ObjCBool = false
            let backupExists = FileManager.default.fileExists(
                atPath: legacyBackupURL.path, isDirectory: &isDirectory
            )
            do {
                // A directory is not a usable previous-settings backup.
                if isDirectory.boolValue {
                    throw CocoaError(.fileWriteFileExists)
                }
                if !backupExists {
                    try FileManager.default.copyItem(at: url, to: legacyBackupURL)
                }
            } catch {
                throw ConfigStoreError.backupFailed(legacyBackupURL, underlying: error)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
