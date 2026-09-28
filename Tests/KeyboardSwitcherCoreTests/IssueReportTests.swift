import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct IssueReportTests {
    @Test func bugReportFillsTheTemplateVersionFields() {
        let url = IssueReport.bugReportURL(
            appVersion: "0.10.0",
            macOSVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 1)
        )

        #expect(url?.absoluteString
            == "https://github.com/ShunmeiCho/cmd-ime/issues/new?template=bug_report.yml&version=0.10.0&macos=macOS%2015.5.1")
        #expect(IssueReport.macOSName(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
            == "macOS 27.0")
    }
}
