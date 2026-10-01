import Foundation

/// Finding the newest release when GitHub's REST API refuses: it allows 60 requests an hour per public
/// IP without an account, and on a shared office or school network that budget runs out.
public enum ReleaseLookup {
    /// `https://github.com/<repo>/releases/latest` redirects to `.../releases/tag/v0.13.1`, which is not
    /// rate limited like the API. Nil when the final URL is not a tag page (no release yet).
    public static func version(fromLatestReleaseURL url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else { return nil }
        let tag = parts[parts.count - 1]
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        guard let first = version.first, first.isNumber else { return nil }
        return version
    }

    /// GitHub answers a spent budget with 403 or 429 and `X-RateLimit-Remaining: 0`.
    public static func isRateLimited(status: Int, remaining: String?) -> Bool {
        (status == 403 || status == 429) && remaining?.trimmingCharacters(in: .whitespaces) == "0"
    }

    /// `X-RateLimit-Reset` is the reset time in seconds since 1970.
    public static func resetDate(header: String?) -> Date? {
        guard let header, let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
