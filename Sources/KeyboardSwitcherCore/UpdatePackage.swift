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

/// What the background update reminder remembers between launches.
public struct UpdateReminderState: Equatable, Sendable {
    public var isEnabled: Bool
    public var lastCheck: Date?
    public var lastNotifiedVersion: String?
    public var skippedVersion: String?

    public init(isEnabled: Bool = true, lastCheck: Date? = nil,
                lastNotifiedVersion: String? = nil, skippedVersion: String? = nil) {
        self.isEnabled = isEnabled
        self.lastCheck = lastCheck
        self.lastNotifiedVersion = lastNotifiedVersion
        self.skippedVersion = skippedVersion
    }
}

public enum UpdateReminderPolicy {
    /// At most one background check a day.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    public static func shouldCheck(now: Date, state: UpdateReminderState) -> Bool {
        guard state.isEnabled else { return false }
        guard let last = state.lastCheck else { return true }
        // A clock set backwards must not silence the reminder for good.
        return now < last || now.timeIntervalSince(last) >= checkInterval
    }

    /// One notification per version, and none for a version the user chose to skip.
    public static func shouldNotify(latest: String, current: String, state: UpdateReminderState) -> Bool {
        guard state.isEnabled, AppVersion(latest) > AppVersion(current) else { return false }
        return latest != state.lastNotifiedVersion && latest != state.skippedVersion
    }
}
