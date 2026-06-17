import Foundation

public struct ConfigLoadResult: Equatable, Sendable {
    public let config: SwitcherConfig
    /// Non-nil when an existing on-disk config was unreadable and got moved aside for recovery.
    public let recoveredBackupURL: URL?

    public init(config: SwitcherConfig, recoveredBackupURL: URL?) {
        self.config = config
        self.recoveredBackupURL = recoveredBackupURL
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

    public func load() throws -> SwitcherConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SwitcherConfig.self, from: data)
    }

    public func loadOrDefault() throws -> SwitcherConfig {
        FileManager.default.fileExists(atPath: url.path) ? try load() : .default
    }

    /// Loads the config, but never silently destroys an existing-yet-unreadable file.
    /// - File absent: returns `.default` with no backup.
    /// - File decodes: returns it.
    /// - File present but unreadable/corrupt: moves it aside to a unique
    ///   `<name>.corrupt.<uuid>` backup,
    ///   returns `.default`, and reports the backup URL so the caller can surface it.
    public func loadOrRecover() throws -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ConfigLoadResult(config: .default, recoveredBackupURL: nil)
        }
        do {
            return ConfigLoadResult(config: try load(), recoveredBackupURL: nil)
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

    public func save(_ config: SwitcherConfig) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
