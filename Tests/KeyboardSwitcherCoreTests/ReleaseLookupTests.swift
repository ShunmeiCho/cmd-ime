import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct ReleaseLookupTests {
    @Test("the latest-release redirect names the version")
    func versionFromTagPage() throws {
        let url = try #require(URL(string: "https://github.com/ShunmeiCho/cmd-ime/releases/tag/v0.13.1"))
        #expect(ReleaseLookup.version(fromLatestReleaseURL: url) == "0.13.1")
    }

    @Test("a redirect that is not a tag page gives no version")
    func noVersionWithoutTag() throws {
        let releases = try #require(URL(string: "https://github.com/ShunmeiCho/cmd-ime/releases"))
        let oddTag = try #require(URL(string: "https://github.com/ShunmeiCho/cmd-ime/releases/tag/nightly"))
        #expect(ReleaseLookup.version(fromLatestReleaseURL: releases) == nil)
        #expect(ReleaseLookup.version(fromLatestReleaseURL: oddTag) == nil)
    }

    @Test("a spent rate limit is 403 or 429 with nothing remaining")
    func rateLimit() {
        #expect(ReleaseLookup.isRateLimited(status: 403, remaining: "0"))
        #expect(ReleaseLookup.isRateLimited(status: 429, remaining: "0"))
        #expect(!ReleaseLookup.isRateLimited(status: 403, remaining: "12"))
        #expect(!ReleaseLookup.isRateLimited(status: 404, remaining: "0"))
        #expect(!ReleaseLookup.isRateLimited(status: 403, remaining: nil))
    }

    @Test("the reset header is seconds since 1970")
    func resetDate() {
        #expect(ReleaseLookup.resetDate(header: "1790836503") == Date(timeIntervalSince1970: 1_790_836_503))
        #expect(ReleaseLookup.resetDate(header: "soon") == nil)
    }
}
