import AppKit
import KeyboardSwitcherCore
import UniformTypeIdentifiers

/// Name and icon for an app id (a bundle id, or the executable path of an app without one), the
/// same key App Memory and App Rules use.
struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String

    /// Nil when nothing on disk answers to the id any more.
    var url: URL? { AppMetadataCache.shared.entry(for: id).url }

    var isInstalled: Bool { AppMetadataCache.shared.entry(for: id).isInstalled }

    var icon: NSImage { AppMetadataCache.shared.entry(for: id).icon }

    /// `fallbackName` is what was stored with a rule, for an app that has since been removed.
    init(id: String, fallbackName: String? = nil) {
        self.id = id
        name = AppMetadataCache.shared.entry(for: id).displayName
            ?? fallbackName
            ?? (id.hasPrefix("/") ? URL(fileURLWithPath: id).lastPathComponent : id)
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The app an .app bundle on disk stands for; nil for anything that is not one.
    init?(bundleURL url: URL) {
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let id = AppRuleBoard.appID(bundleIdentifier: bundle.bundleIdentifier,
                                          executablePath: bundle.executableURL?.path) else { return nil }
        self.init(id: id, name: Self.displayName(of: url))
    }

    var candidate: AppCandidate { AppCandidate(id: id, name: name) }

    /// The folders apps are normally installed in, for the rule board's search. Subfolders such as
    /// Utilities and vendor folders are searched too (`AppBundleScan`).
    private static var appFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/System/Applications"].map { URL(fileURLWithPath: $0) }
            + [home.appendingPathComponent("Applications")]
    }

    /// Apps installed in the usual folders. It walks folders and reads every bundle, so call it
    /// off the main thread.
    static func installed() -> [InstalledApp] {
        AppBundleScan.appBundles(in: appFolders).compactMap { InstalledApp(bundleURL: $0) }
    }

    fileprivate static func displayName(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Regular apps running now, CmdIME excluded, by name: suggestions for a new rule.
    static func running() -> [InstalledApp] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> InstalledApp? in
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier ?? app.executableURL?.path,
                  id != own else { return nil }
            return InstalledApp(id: id, name: app.localizedName ?? InstalledApp(id: id).name)
        }
        return Array(Set(apps)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick any app from disk; nil when cancelled.
    @MainActor
    static func choose() -> InstalledApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add Rule")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return InstalledApp(bundleURL: url)
    }
}

/// Name, icon and install state per app id, looked up once. The Apps page redraws on every input
/// source change and app switch, and LaunchServices lookups, file checks and icon loads are too
/// slow to repeat for every chip and row each time. The page clears it when it appears and when
/// an app launches or quits, since an app may have been installed or removed meanwhile.
final class AppMetadataCache: @unchecked Sendable {
    struct Entry {
        let url: URL?
        let isInstalled: Bool
        /// Nil when nothing on disk answers to the id.
        let displayName: String?
        let icon: NSImage
    }

    static let shared = AppMetadataCache()

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func entry(for id: String) -> Entry {
        if let cached = lock.withLock({ entries[id] }) { return cached }
        let entry = Self.lookUp(id)
        lock.withLock { entries[id] = entry }
        return entry
    }

    func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    private static func lookUp(_ id: String) -> Entry {
        let url = id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let installedURL = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        return Entry(
            url: url,
            isInstalled: installedURL != nil,
            displayName: installedURL.map(InstalledApp.displayName(of:)),
            icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
        )
    }
}
