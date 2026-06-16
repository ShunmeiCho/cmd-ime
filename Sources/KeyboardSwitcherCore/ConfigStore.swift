import Foundation

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
