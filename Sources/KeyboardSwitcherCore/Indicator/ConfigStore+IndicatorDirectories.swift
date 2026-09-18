import Foundation

public extension ConfigStore {
    /// Imported font files, next to the config file.
    var fontsDirectoryURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("fonts", isDirectory: true)
    }

    /// User theme files, next to the config file.
    var themesDirectoryURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("themes", isDirectory: true)
    }
}

extension FileManager {
    /// Visible regular files directly inside `directory`, sorted by name. Symbolic
    /// links are skipped so a store never reads or deletes outside its directory.
    /// A missing directory is an empty listing.
    func indicatorStoreFiles(in directory: URL, extensions: [String]) throws -> [URL] {
        guard fileExists(atPath: directory.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        return try contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .filter { url in
                guard extensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func indicatorFileSize(at url: URL) -> Int? {
        (try? attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
