import Foundation
import KeyboardSwitcherCore

struct UpdateCheckResult: Equatable {
    var currentVersion: String
    var latestVersion: String
    var releaseURL: URL
    var isUpdateAvailable: Bool
    /// What changed, condensed from the release's notes; empty when the release has none.
    var notes = ReleaseNotesSummary()
}

enum UpdateServiceError: Error, LocalizedError {
    case invalidResponse
    /// GitHub's API budget for this network (60 requests an hour without an account) is spent.
    case rateLimited(until: Date?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "Could not read the latest CmdIME release.")
        case let .rateLimited(until?):
            String(localized: "GitHub is limiting requests from this network until \(until.formatted(date: .omitted, time: .shortened)). CmdIME will check again later.")
        case .rateLimited(nil):
            String(localized: "GitHub is limiting requests from this network right now. CmdIME will check again later.")
        }
    }
}

final class UpdateService: Sendable {
    private let releasesURL = URL(
        string: "https://api.github.com/repos/ShunmeiCho/cmd-ime/releases?per_page=30"
    )!

    private let latestReleaseURL = URL(string: "https://github.com/ShunmeiCho/cmd-ime/releases/latest")!

    /// The API first, for the release notes. When it refuses or fails, the release page's redirect
    /// still names the newest version (without notes); only if both fail is the API's error shown.
    func check(currentVersion: String) async throws -> UpdateCheckResult {
        let apiError: Error
        do {
            return try await checkThroughAPI(currentVersion: currentVersion)
        } catch {
            apiError = error
        }
        if let result = try? await checkThroughLatestRedirect(currentVersion: currentVersion) {
            return result
        }
        throw apiError
    }

    private func checkThroughLatestRedirect(currentVersion: String) async throws -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              let latestVersion = ReleaseLookup.version(fromLatestReleaseURL: finalURL) else {
            throw UpdateServiceError.invalidResponse
        }
        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: finalURL,
            isUpdateAvailable: AppVersion(latestVersion) > AppVersion(currentVersion)
        )
    }

    private func checkThroughAPI(currentVersion: String) async throws -> UpdateCheckResult {
        let (data, response) = try await URLSession.shared.data(from: releasesURL)
        guard let httpResponse = response as? HTTPURLResponse else { throw UpdateServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if ReleaseLookup.isRateLimited(status: httpResponse.statusCode,
                                           remaining: httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining")) {
                throw UpdateServiceError.rateLimited(
                    until: ReleaseLookup.resetDate(header: httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")))
            }
            throw UpdateServiceError.invalidResponse
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard let release = releases
            .filter({ !$0.isDraft })
            .max(by: { AppVersion($0.tagName) < AppVersion($1.tagName) }) else {
            throw UpdateServiceError.invalidResponse
        }
        let latestVersion = release.tagName.removingLeadingVersionPrefix()
        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: release.htmlURL,
            isUpdateAvailable: AppVersion(latestVersion) > AppVersion(currentVersion),
            notes: ReleaseNotesSummary.parse(release.body ?? "")
        )
    }
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var htmlURL: URL
    var isDraft: Bool
    var body: String?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case isDraft = "draft"
        case body
    }
}

private extension String {
    func removingLeadingVersionPrefix() -> String {
        hasPrefix("v") || hasPrefix("V") ? String(dropFirst()) : self
    }
}
