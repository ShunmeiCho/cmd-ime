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

    /// Whether an app is somewhere the user types, for App Memory: a regular app, or a launcher,
    /// which is an accessory app but has a text field of its own.
    public static func countsAsApp(bundleID: String?, isRegularApp: Bool) -> Bool {
        isRegularApp || bundleID.map(isLauncher) ?? false
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
