import Testing
@testable import KeyboardSwitcherCore

struct InterfaceLanguageTests {
    @Test("each choice stores the AppleLanguages list macOS reads; System stores none")
    func storesTheListMacOSReads() {
        #expect(InterfaceLanguage.defaultsKey == "AppleLanguages")
        #expect(InterfaceLanguage.system.storedValue == nil)
        #expect(InterfaceLanguage.english.storedValue == ["en"])
        #expect(InterfaceLanguage.simplifiedChinese.storedValue == ["zh-Hans"])
        #expect(InterfaceLanguage.japanese.storedValue == ["ja"])
    }

    @Test("a stored choice reads back as the same choice", arguments: InterfaceLanguage.allCases)
    func storedChoiceReadsBack(language: InterfaceLanguage) {
        #expect(InterfaceLanguage(stored: language.storedValue) == language)
    }

    @Test("a missing, empty or unknown list reads as System", arguments: [nil, [], ["fr"], ["zh-Hant"], ["english"]] as [[String]?])
    func unknownListReadsAsSystem(stored: [String]?) {
        #expect(InterfaceLanguage(stored: stored) == .system)
    }

    @Test("the first entry decides, and a region suffix still names the language")
    func firstEntryWithRegionDecides() {
        #expect(InterfaceLanguage(stored: ["ja-JP"]) == .japanese)
        #expect(InterfaceLanguage(stored: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(InterfaceLanguage(stored: ["en-GB", "ja"]) == .english)
        #expect(InterfaceLanguage(stored: ["fr", "ja"]) == .system)
    }
}
