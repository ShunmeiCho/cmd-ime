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

    func testJapanesePaletteDoesNotBeatRealInputMethod() {
        var config = SwitcherConfig.default
        config.pinInputSourceID("com.apple.50onPaletteIM", for: .japanese)

        let sources = [
            InputSourceInfo(
                id: "com.apple.50onPaletteIM",
                localizedName: "Japanese Kana Palette",
                languages: ["ja"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .japanese, sources: sources, config: config)

        XCTAssertEqual(match?.id, "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese")
    }

    func testSelectableSourcesExcludeAuxiliaryInputSources() {
        let sources = [
            InputSourceInfo(
                id: "com.apple.keylayout.ABC",
                localizedName: "ABC",
                languages: ["en"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.50onPaletteIM",
                localizedName: "Japanese Kana Palette",
                languages: ["ja"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.CharacterPaletteIM",
                localizedName: "Emoji & Symbols",
                languages: ["en"],
                isSelectCapable: true
            ),
        ]

        let selectable = InputSourceMatcher.selectableSources(from: sources)

        XCTAssertEqual(selectable.map(\.id), ["com.apple.keylayout.ABC"])
    }

    func testDisplayLanguagesTruncatesLongLanguageLists() {
        let source = InputSourceInfo(
            id: "abc",
            localizedName: "ABC",
            languages: ["en", "af", "asa", "bem", "bez", "ca"],
            isSelectCapable: true
        )

        XCTAssertEqual(source.displayLanguages, "en, af, asa, bem +2 more")
    }
}
