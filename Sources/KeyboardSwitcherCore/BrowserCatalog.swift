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
    ]

    /// The browsers the address read was measured on. The rest are listed because they share an
    /// engine with one of these, and nobody has run the read against them yet.
    private static let measured: Set<String> = ["com.apple.Safari", "com.google.Chrome"]

    public static var bundleIDs: Set<String> { Set(engines.keys) }

    /// Nil for an app that is not a listed browser.
    public static func engine(for bundleID: String) -> Engine? {
        engines[bundleID]
    }

    public static func isBrowser(_ bundleID: String) -> Bool {
        engines[bundleID] != nil
    }

    public static func isMeasured(_ bundleID: String) -> Bool {
        measured.contains(bundleID)
    }
}
