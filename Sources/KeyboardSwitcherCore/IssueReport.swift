import Foundation

/// The prefilled bug report behind About > Report an Issue.
public enum IssueReport {
    /// A new issue from `.github/ISSUE_TEMPLATE/bug_report.yml` with the CmdIME and macOS
    /// versions filled in. The query keys are the template's field ids.
    public static func bugReportURL(appVersion: String, macOSVersion: OperatingSystemVersion) -> URL? {
        var components = URLComponents(string: "https://github.com/\(UpdatePackage.repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: appVersion),
            URLQueryItem(name: "macos", value: macOSName(macOSVersion)),
        ]
        return components?.url
    }

    /// "macOS 15.5", or "macOS 15.5.1" when there is a patch, as the template's placeholder writes it.
    static func macOSName(_ version: OperatingSystemVersion) -> String {
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        return "macOS \(version.majorVersion).\(version.minorVersion)\(patch)"
    }
}
