import AppKit
import KeyboardSwitcherCore
import UniformTypeIdentifiers

/// Name and icon for an app id (a bundle id, or the executable path of an app without one), the
/// same key App Memory and App Rules use.
struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String

    /// Nil when nothing on disk answers to the id any more.
    var url: URL? {
        id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    var isInstalled: Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    var icon: NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// `fallbackName` is what was stored with a rule, for an app that has since been removed.
    init(id: String, fallbackName: String? = nil) {
        self.id = id
        let url = id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        if let url, FileManager.default.fileExists(atPath: url.path) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            name = fallbackName ?? (id.hasPrefix("/") ? URL(fileURLWithPath: id).lastPathComponent : id)
        }
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

    /// The folders apps are normally installed in, for the rule board's search.
    private static var appFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0) } + [home.appendingPathComponent("Applications")]
    }

    /// Apps installed in the usual folders. It reads every bundle, so call it off the main thread.
    static func installed() -> [InstalledApp] {
        appFolders.flatMap { folder -> [InstalledApp] in
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            return contents.compactMap { InstalledApp(bundleURL: $0) }
        }
    }

    private static func displayName(of url: URL) -> String {
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
        panel.prompt = "Add Rule"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return InstalledApp(bundleURL: url)
    }
}
