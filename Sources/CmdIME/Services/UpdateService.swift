import Foundation
import KeyboardSwitcherCore

struct UpdateCheckResult: Equatable {
    var currentVersion: String
    var latestVersion: String
    var releaseURL: URL
    var isUpdateAvailable: Bool
}

enum UpdateServiceError: Error, LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Could not read the latest CmdIME release."
        }
    }
}

final class UpdateService: Sendable {
    private let releasesURL = URL(
        string: "https://api.github.com/repos/ShunmeiCho/cmd-ime/releases?per_page=30"
    )!

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        let (data, response) = try await URLSession.shared.data(from: releasesURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
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
            isUpdateAvailable: AppVersion(latestVersion) > AppVersion(currentVersion)
        )
    }
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var htmlURL: URL
    var isDraft: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case isDraft = "draft"
    }
}

private extension String {
    func removingLeadingVersionPrefix() -> String {
        hasPrefix("v") || hasPrefix("V") ? String(dropFirst()) : self
    }
}
