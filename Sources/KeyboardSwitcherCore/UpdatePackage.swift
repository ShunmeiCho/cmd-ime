import Foundation

/// Where a release's files live and how its published checksum is read.
public enum UpdatePackage {
    public static let repository = "ShunmeiCho/cmd-ime"

    /// The zip and the `.sha256` file that `script/package_app.sh` publishes beside it.
    public static func assetURLs(version: String) -> (zip: URL, checksum: URL)? {
        // Only a plain X.Y.Z may reach a URL.
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              let zip = URL(string: "https://github.com/\(repository)/releases/download/v\(version)/CmdIME-\(version).zip")
        else { return nil }
        return (zip, zip.appendingPathExtension("sha256"))
    }

    /// `shasum -a 256` output: the digest, two spaces, the file name. Only the digest matters.
    public static func publishedChecksum(from text: String) -> String? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first.map(String.init) else { return nil }
        let digest = token.lowercased()
        return digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil ? digest : nil
    }
}

/// How often the background check may run. Six hours is the default: a fix reaches a
/// windowless app the same day, and the unauthenticated GitHub limit (60 requests an hour)
/// stays far away.
public enum UpdateCheckFrequency: String, CaseIterable, Sendable {
    case sixHours
    case daily
    case weekly

    public var interval: TimeInterval {
        switch self {
        case .sixHours: 6 * 60 * 60
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }

    public var title: String {
        switch self {
        case .sixHours: "6 hours"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

/// What the background update reminder remembers between launches.
public struct UpdateReminderState: Equatable, Sendable {
    public var isEnabled: Bool
    public var frequency: UpdateCheckFrequency
    /// Off: updates still show in the settings window, but no system notification is posted.
    public var notifies: Bool
    public var lastCheck: Date?
    public var lastNotifiedVersion: String?
    public var skippedVersion: String?

    public init(isEnabled: Bool = true, frequency: UpdateCheckFrequency = .sixHours, notifies: Bool = true,
                lastCheck: Date? = nil, lastNotifiedVersion: String? = nil, skippedVersion: String? = nil) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.notifies = notifies
        self.lastCheck = lastCheck
        self.lastNotifiedVersion = lastNotifiedVersion
        self.skippedVersion = skippedVersion
    }
}

public enum UpdateReminderPolicy {
    public static func shouldCheck(now: Date, state: UpdateReminderState) -> Bool {
        guard state.isEnabled else { return false }
        guard let last = state.lastCheck else { return true }
        // A clock set backwards must not silence the reminder for good.
        return now < last || now.timeIntervalSince(last) >= state.frequency.interval
    }

    /// One notification per version, and none for a version the user chose to skip.
    public static func shouldNotify(latest: String, current: String, state: UpdateReminderState) -> Bool {
        guard state.isEnabled, state.notifies, AppVersion(latest) > AppVersion(current) else { return false }
        return latest != state.lastNotifiedVersion && latest != state.skippedVersion
    }
}
