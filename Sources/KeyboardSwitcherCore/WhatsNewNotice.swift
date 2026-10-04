/// Eligibility for the settings notice, independent of persistence and UI state.
public enum WhatsNewNotice {
    public static func shouldShow(
        lastSeen: String?,
        current: String,
        hasCompletedSetup: Bool,
        isFreshConfig: Bool
    ) -> Bool {
        guard !isFreshConfig, hasCompletedSetup,
              let currentVersion = majorMinor(current) else { return false }
        guard let lastSeen else { return true }
        guard let seenVersion = majorMinor(lastSeen) else { return false }
        return seenVersion < currentVersion
    }

    /// One line per release, keyed by major.minor. A release without an entry shows no notice,
    /// so a line written for an older release never comes back after a later upgrade.
    static let messages: [String: String] = [
        "0.12": "New in 0.12: App Rules on the Apps page, a bubble for every switch, Peek, and settings export and import.",
        "0.17": "New in 0.17: Raycast, Spotlight and Alfred count as apps, and a launcher opens in English unless you give it a rule.",
        "0.16": "New in 0.16: Toggle, one key between two slots; an optional space between Chinese and English; Terminal.app tabs followed by program rules.",
        "0.15": "New in 0.15: an input source per program in the terminal on the Apps page: English at the shell prompt, another slot inside an agent CLI.",
        "0.14": "New in 0.14: an input source per website on the Apps page, and shortcuts that tell the left modifier key from the right.",
        "0.13": "New in 0.13: settings in Chinese and Japanese, and one bubble per switch: the macOS badge stays hidden while CmdIME's is on.",
    ]

    public static func message(for version: String) -> String? {
        guard let (major, minor) = majorMinor(version) else { return nil }
        return messages["\(major).\(minor)"].map { CoreLocalization.text($0) }
    }

    /// Accept major.minor or major.minor.patch, with ASCII numeric components only.
    /// Validate the patch too, but never use it to decide whether to show again.
    private static func majorMinor(_ version: String) -> (Int, Int)? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return (numbers[0], numbers[1])
    }
}
