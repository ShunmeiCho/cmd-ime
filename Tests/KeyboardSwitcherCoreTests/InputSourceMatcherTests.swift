import XCTest
@testable import KeyboardSwitcherCore

final class InputSourceMatcherTests: XCTestCase {
    func testPreferredIDBeatsLanguageFallback() {
        var config = SwitcherConfig.default
        config.pinInputSourceID("custom.zh", for: .chinese)

        let sources = [
            InputSourceInfo(
                id: "first.zh",
                localizedName: "Chinese",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "custom.zh",
                localizedName: "My Pinyin",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .chinese, sources: sources, config: config)

        XCTAssertEqual(match?.id, "custom.zh")
    }

    func testLanguageFallbackFindsJapanese() {
        let sources = [
            InputSourceInfo(
                id: "emoji",
                localizedName: "Emoji",
                languages: ["en"],
                isSelectCapable: false
            ),
            InputSourceInfo(
                id: "jp",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .japanese, sources: sources, config: .default)

        XCTAssertEqual(match?.id, "jp")
    }
}

