import Foundation

/// Launchers whose panel takes the keyboard without becoming the frontmost app, by bundle id.
/// While one shows, App Memory and App Rules treat it as the app in front. Measured on macOS 27:
/// Raycast and Spotlight (`com.apple.campo`) never change `frontmostApplication` or the menu bar
/// owner, and both are accessory apps. Alfred is listed unmeasured; `com.apple.Spotlight` is the
/// Spotlight process on releases before 27.
public enum LauncherCatalog {
    private static let bundleIDs: Set<String> = [
        "com.raycast.macos",
        "com.apple.campo",
        "com.apple.Spotlight",
        "com.runningwithcrayons.Alfred",
    ]

    public static func isLauncher(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    /// The name to show for a launcher whose app name hides it: on macOS 27 Spotlight is the Siri AI app.
    public static func displayName(for appID: String) -> String? {
        appID == spotlightOnSiriAI ? "Spotlight (Siri AI)" : nil
    }

    private static let spotlightOnSiriAI = "com.apple.campo"

    /// Whether an app is somewhere the user types, for App Memory: a regular app, or a launcher,
    /// which is an accessory app but has a text field of its own.
    public static func countsAsApp(bundleID: String?, isRegularApp: Bool) -> Bool {
        isRegularApp || bundleID.map(isLauncher) ?? false
    }
}

/// What a launcher with no rule and nothing remembered opens in. Persisted as the optional config
/// key `launcherDefault`; a missing or unreadable one is `.english`, the behaviour 0.17.0 shipped.
public enum LauncherDefault: Hashable, Sendable {
    /// The first slot whose language is English.
    case english
    /// This slot; a slot deleted since falls back to English.
    case slot(InputRole)
    /// Whatever other apps without a rule get (the default slot, or no change).
    case sameAsOtherApps
}

extension LauncherDefault: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case slot
    }

    private enum Kind: String, Codable {
        case english
        case slot
        case sameAsOtherApps = "apps"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .english: self = .english
        case .slot: self = .slot(try container.decode(InputRole.self, forKey: .slot))
        case .sameAsOtherApps: self = .sameAsOtherApps
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .english:
            try container.encode(Kind.english, forKey: .kind)
        case .slot(let slot):
            try container.encode(Kind.slot, forKey: .kind)
            try container.encode(slot, forKey: .slot)
        case .sameAsOtherApps:
            try container.encode(Kind.sameAsOtherApps, forKey: .kind)
        }
    }
}

/// Which launcher panel has the keyboard, from repeated reads of the focused application.
/// Pure: the caller reads Accessibility and names the result. A single failed read does not end
/// a panel that is showing (a read can fail while windows change); a second one in a row does.
public struct LauncherPresence: Equatable, Sendable {
    public enum Read: Equatable, Sendable {
        /// The focused application is a catalog launcher with this pid.
        case launcher(Int32)
        /// The focused application is anything else.
        case other
        /// The focused application could not be read.
        case failed
    }

    /// The launcher whose panel shows, or nil.
    public private(set) var launcherPID: Int32?
    private var failedReadsInARow = 0
    private static let failedReadsToHide = 2

    public init() {}

    /// Takes one read; true when `launcherPID` changed.
    public mutating func record(_ read: Read) -> Bool {
        let before = launcherPID
        switch read {
        case .launcher(let pid):
            failedReadsInARow = 0
            launcherPID = pid
        case .other:
            failedReadsInARow = 0
            launcherPID = nil
        case .failed:
            failedReadsInARow += 1
            if failedReadsInARow >= Self.failedReadsToHide {
                launcherPID = nil
            }
        }
        return launcherPID != before
    }
}
