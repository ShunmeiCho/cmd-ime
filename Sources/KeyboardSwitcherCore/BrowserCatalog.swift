import Foundation

/// The browsers whose page address CmdIME reads for website rules. An app that is not listed is
/// never read.
public enum BrowserCatalog {
    public enum Engine: String, Sendable {
        case webkit
        case chromium
        case gecko
    }

    private static let engines: [String: Engine] = [
        "com.apple.Safari": .webkit,
        "com.apple.SafariTechnologyPreview": .webkit,
        "com.google.Chrome": .chromium,
        "org.chromium.Chromium": .chromium,
        "company.thebrowser.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
        "com.brave.Browser.beta": .chromium,
        "com.brave.Browser.nightly": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
        "org.chromium.Thorium": .chromium,
        "org.mozilla.firefox": .gecko,
        "org.mozilla.firefoxdeveloperedition": .gecko,
        "org.mozilla.nightly": .gecko,
        "app.zen-browser.zen": .gecko,
        "company.thebrowser.dia": .chromium,
        "net.imput.helium": .chromium,
        // Not in Input Source Pro's list; added when its owner's read was measured (2026-10-02).
        "at.studio.AsideBrowser": .chromium,
    ]

    /// The browsers the address read was measured on. The rest are listed because they share an
    /// engine with one of these, and nobody has run the read against them yet.
    private static let measured: Set<String> = ["com.apple.Safari", "com.google.Chrome", "at.studio.AsideBrowser"]

    public static var bundleIDs: Set<String> { Set(engines.keys) }

    /// Nil for an app that is not a listed browser.
    public static func engine(for bundleID: String) -> Engine? {
        engines[bundleID]
    }

    public static func isBrowser(_ bundleID: String) -> Bool {
        engines[bundleID] != nil
    }

    /// Whether an app says it opens web pages: its Info.plist `CFBundleURLTypes` lists `http` or
    /// `https`. That is how macOS itself decides what may be the default browser, so a browser
    /// this catalog has never heard of is still read for website rules. A few apps that are not
    /// browsers register the schemes too (a downloader, a link picker); reading them finds no
    /// page and changes nothing.
    public static func declaresWebSchemes(urlTypes: Any?) -> Bool {
        guard let types = urlTypes as? [[String: Any]] else { return false }
        return types.contains { type in
            (type["CFBundleURLSchemes"] as? [String] ?? []).contains { webSchemes.contains($0.lowercased()) }
        }
    }

    private static let webSchemes: Set<String> = ["http", "https"]

    public static func isMeasured(_ bundleID: String) -> Bool {
        measured.contains(bundleID)
    }
}
