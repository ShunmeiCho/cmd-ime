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
