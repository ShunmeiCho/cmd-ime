import Foundation

/// Finds .app bundles for the Apps page's search and tells app bundles apart from other files
/// dropped on its rule board.
public enum AppBundleScan {
    /// How many folder levels below each root are searched: enough for vendor folders such as
    /// /Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app or /Applications/Vendor/Suite/X.app.
    public static let defaultMaxDepth = 3

    /// Every .app under `roots`, down to `maxDepth` folders below each root (the root's own
    /// entries are depth 0). Bundles are never descended into, hidden items are skipped, and a
    /// bundle reachable from two roots is listed once, in the order found.
    public static func appBundles(
        in roots: [URL],
        maxDepth: Int = defaultMaxDepth,
        fileManager: FileManager = .default
    ) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        var pending = roots.map { (folder: $0, depth: 0) }
        while !pending.isEmpty {
            let (folder, depth) = pending.removeFirst()
            let entries = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                if isAppBundle(entry) {
                    if seen.insert(entry.standardizedFileURL.path).inserted { found.append(entry) }
                } else if depth < maxDepth, isFolder(entry) {
                    pending.append((entry, depth + 1))
                }
            }
        }
        return found
    }

    /// Whether a URL names an application bundle by its extension. Anything else dropped on the
    /// board (a document, a folder, a disk image) is not an app.
    public static func isAppBundle(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
