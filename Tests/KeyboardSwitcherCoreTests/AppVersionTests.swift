import XCTest
@testable import KeyboardSwitcherCore

final class AppVersionTests: XCTestCase {
    func testComparesPatchVersions() {
        XCTAssertGreaterThan(AppVersion("0.1.11"), AppVersion("0.1.10"))
    }

    func testIgnoresLeadingVPrefix() {
        XCTAssertEqual(AppVersion("v0.1.10"), AppVersion("0.1.10"))
    }

    func testMissingComponentsCompareAsZero() {
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
    }

    func testIgnoresPrereleaseSuffixForUpdateChecks() {
        XCTAssertEqual(AppVersion("1.2.0-beta.1"), AppVersion("1.2.0"))
    }
}
