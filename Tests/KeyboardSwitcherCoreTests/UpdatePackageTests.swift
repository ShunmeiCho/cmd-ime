import XCTest
@testable import KeyboardSwitcherCore

final class UpdatePackageTests: XCTestCase {
    func testAssetURLsFollowTheReleaseLayoutAndRejectAnythingButPlainVersions() throws {
        let urls = try XCTUnwrap(UpdatePackage.assetURLs(version: "0.5.1"))
        XCTAssertEqual(urls.zip.absoluteString,
                       "https://github.com/ShunmeiCho/cmd-ime/releases/download/v0.5.1/CmdIME-0.5.1.zip")
        XCTAssertEqual(urls.checksum.absoluteString, urls.zip.absoluteString + ".sha256")
        for bad in ["", "v0.5.1", "0.5", "0.5.1-beta", "../0.5.1", "0.5.1/x"] {
            XCTAssertNil(UpdatePackage.assetURLs(version: bad), bad)
        }
    }

    func testPublishedChecksumReadsTheDigestOnly() {
        let digest = String(repeating: "ab", count: 32)
        XCTAssertEqual(UpdatePackage.publishedChecksum(from: "\(digest)  CmdIME-0.5.1.zip\n"), digest)
        XCTAssertEqual(UpdatePackage.publishedChecksum(from: digest.uppercased()), digest)
        XCTAssertNil(UpdatePackage.publishedChecksum(from: "Not Found"))
        XCTAssertNil(UpdatePackage.publishedChecksum(from: String(digest.dropLast())))
        XCTAssertNil(UpdatePackage.publishedChecksum(from: ""))
    }

    func testBackgroundCheckRunsAtMostEverySixHoursAndOnlyWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateReminderPolicy.shouldCheck(now: now, state: .init()))
        XCTAssertFalse(UpdateReminderPolicy.shouldCheck(now: now, state: .init(isEnabled: false)))
        XCTAssertFalse(UpdateReminderPolicy.shouldCheck(now: now, state: .init(lastCheck: now.addingTimeInterval(-3600))))
        XCTAssertTrue(UpdateReminderPolicy.shouldCheck(now: now, state: .init(lastCheck: now.addingTimeInterval(-6 * 3600))))
        XCTAssertFalse(UpdateReminderPolicy.shouldCheck(now: now, state: .init(lastCheck: now.addingTimeInterval(-6 * 3600 + 1))))
        // A clock moved backwards still checks.
        XCTAssertTrue(UpdateReminderPolicy.shouldCheck(now: now, state: .init(lastCheck: now.addingTimeInterval(500))))
    }

    func testEachVersionNotifiesOnceAndSkippedVersionsStayQuiet() {
        XCTAssertTrue(UpdateReminderPolicy.shouldNotify(latest: "0.6.0", current: "0.5.1", state: .init()))
        XCTAssertFalse(UpdateReminderPolicy.shouldNotify(latest: "0.5.1", current: "0.5.1", state: .init()))
        XCTAssertFalse(UpdateReminderPolicy.shouldNotify(latest: "0.6.0", current: "0.5.1",
                                                         state: .init(lastNotifiedVersion: "0.6.0")))
        XCTAssertFalse(UpdateReminderPolicy.shouldNotify(latest: "0.6.0", current: "0.5.1",
                                                         state: .init(skippedVersion: "0.6.0")))
        XCTAssertTrue(UpdateReminderPolicy.shouldNotify(latest: "0.6.1", current: "0.5.1",
                                                        state: .init(lastNotifiedVersion: "0.6.0", skippedVersion: "0.6.0")))
        XCTAssertFalse(UpdateReminderPolicy.shouldNotify(latest: "0.6.0", current: "0.5.1", state: .init(isEnabled: false)))
    }
}
