import XCTest
@testable import KeyboardSwitcherCore

final class InputSourceKindTests: XCTestCase {
    func testPrimaryLanguageWins() {
        let fixtures: [([String], InputSourceKind, String, String)] = [
            (["en", "zh-Hans", "ja"], InputSourceKind.english, "A", "English"),
            (["zh-Hans", "en", "ja"], .chinese, "中", "中文"),
            (["ja", "en", "zh-Hans"], .japanese, "あ", "日本語"),
            ([" EN_us "], .english, "A", "English"),
        ]
        for (languages, expected, symbol, title) in fixtures {
            let source = InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: languages, isSelectCapable: true)
            let kind = InputSourceKind(source: source)
            XCTAssertEqual(kind, expected)
            XCTAssertEqual(kind.symbol(source: source), symbol)
            XCTAssertEqual(kind.title(fallback: "Custom slot"), title)
        }
    }

    func testUnsupportedPrimaryIgnoresSecondaryLanguagesAndMisleadingNames() {
        for language in ["de", "fr", "es", "ko"] {
            for secondary in ["en", "zh-Hans", "ja"] {
                for name in ["Local layout", "ABC", "Japanese Hiragana Kotoeri", "Chinese Pinyin 中文 拼音"] {
                    let source = InputSourceInfo(id: "com.apple.keylayout.us", localizedName: name, languages: [language, secondary], isSelectCapable: true)
                    let kind = InputSourceKind(source: source)
                    XCTAssertEqual(kind, .unknown)
                    XCTAssertEqual(kind.symbol(source: source), source.badgeSymbol)
                    XCTAssertEqual(kind.title(fallback: "My custom slot"), "My custom slot")
                }
            }
        }
    }

    func testNoLanguagePreservesLegacyPresentation() {
        let fixtures: [(String, String, InputSourceKind, String, String)] = [
            ("com.apple.keylayout.ABC", "Layout", InputSourceKind.english, "A", "English"),
            ("layout", "U.S.", .english, "A", "English"),
            ("com.apple.keylayout.us", "Layout", .english, "A", "English"),
            ("layout", "Japanese", .japanese, "あ", "日本語"),
            ("layout", "Hiragana", .japanese, "あ", "日本語"),
            ("com.apple.inputmethod.Kotoeri", "Layout", .japanese, "あ", "日本語"),
            ("layout", "Pinyin", .chinese, "中", "中文"),
            ("layout", "Chinese", .chinese, "中", "中文"),
            ("layout", "Simplified", .chinese, "中", "中文"),
            ("com.apple.inputmethod.SCIM", "Layout", .chinese, "中", "中文"),
            ("layout", "中文", .chinese, "中", "中文"),
            ("layout", "拼音", .chinese, "中", "中文"),
            ("layout", "Other", .unknown, "O", "Custom slot"),
        ]
        for (id, name, expected, symbol, title) in fixtures {
            let source = InputSourceInfo(id: id, localizedName: name, languages: [], isSelectCapable: true)
            let kind = InputSourceKind(source: source)
            XCTAssertEqual(kind, expected)
            XCTAssertEqual(kind.symbol(source: source), symbol)
            XCTAssertEqual(kind.title(fallback: "Custom slot"), title)
        }
    }
}
