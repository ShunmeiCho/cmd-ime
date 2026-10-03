import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct AutoSpaceTests {
    @Test("the character before the caret is Han, an ASCII letter or digit, or something that needs no space", arguments: [
        ("中", AutoSpace.Before.han), ("文字", .han), ("𠀀", .han),
        ("a", .asciiLetterOrDigit), ("Z", .asciiLetterOrDigit), ("7", .asciiLetterOrDigit),
        (" ", .noSpaceNeeded), ("，", .noSpaceNeeded), ("。", .noSpaceNeeded), (".", .noSpaceNeeded),
        ("あ", .noSpaceNeeded), ("é", .noSpaceNeeded), ("\n", .noSpaceNeeded),
    ])
    func classify(text: String, expected: AutoSpace.Before) {
        #expect(AutoSpace.classify(text) == expected)
    }

    @Test("nothing read is unknown")
    func unknown() {
        #expect(AutoSpace.classify(nil) == .unknown)
        #expect(AutoSpace.classify("") == .unknown)
    }

    @Test("English sources go into Latin, Chinese ones into Chinese, Japanese and Korean are left alone")
    func direction() {
        func source(_ language: String) -> InputSourceInfo {
            InputSourceInfo(id: language, localizedName: language, languages: [language], isSelectCapable: true)
        }
        #expect(AutoSpace.direction(switchingTo: source("en")) == .intoLatin)
        #expect(AutoSpace.direction(switchingTo: source("zh-Hans")) == .intoChinese)
        #expect(AutoSpace.direction(switchingTo: source("zh-Hant")) == .intoChinese)
        #expect(AutoSpace.direction(switchingTo: source("ja")) == nil)
        #expect(AutoSpace.direction(switchingTo: source("ko")) == nil)
    }

    @Test("a space is needed after Han going into English, after a letter or digit going into Chinese")
    func needsSpace() {
        #expect(AutoSpace.needsSpace(.intoLatin, before: .han))
        #expect(!AutoSpace.needsSpace(.intoLatin, before: .asciiLetterOrDigit))
        #expect(AutoSpace.needsSpace(.intoChinese, before: .asciiLetterOrDigit))
        #expect(!AutoSpace.needsSpace(.intoChinese, before: .han))
        #expect(!AutoSpace.needsSpace(.intoChinese, before: .noSpaceNeeded))
        #expect(!AutoSpace.needsSpace(.intoLatin, before: .unknown))
    }

    @Test("into English a letter or digit qualifies; into Chinese only a letter; never a shortcut, space or punctuation")
    func qualifies() {
        #expect(AutoSpace.qualifies(.intoLatin, characters: "a", commandControlOrOption: false))
        #expect(AutoSpace.qualifies(.intoLatin, characters: "7", commandControlOrOption: false))
        #expect(AutoSpace.qualifies(.intoChinese, characters: "n", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(.intoChinese, characters: "7", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(.intoLatin, characters: "a", commandControlOrOption: true))
        #expect(!AutoSpace.qualifies(.intoLatin, characters: " ", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(.intoChinese, characters: "(", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(.intoLatin, characters: "", commandControlOrOption: false))
    }

    @Test("after Han, the first English letter gets a space and the second does not")
    func spendsOnce() {
        var state = AutoSpaceState()
        state.read(.han, generation: state.armed(.intoLatin))

        let first = state.keyDown(characters: "E", commandControlOrOption: false)
        let second = state.keyDown(characters: "n", commandControlOrOption: false)
        #expect(first)
        #expect(!second)
    }

    @Test("after English, the first pinyin letter gets a space")
    func intoChinese() {
        var state = AutoSpaceState()
        state.read(.asciiLetterOrDigit, generation: state.armed(.intoChinese))

        let spaced = state.keyDown(characters: "n", commandControlOrOption: false)
        #expect(spaced)
    }

    @Test("a first key that does not qualify ends the chance")
    func otherKeyEnds() {
        var state = AutoSpaceState()
        state.read(.han, generation: state.armed(.intoLatin))

        let space = state.keyDown(characters: " ", commandControlOrOption: false)
        let letter = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!space)
        #expect(!letter)
    }

    @Test("a key typed before the read finishes passes, and the late read is ignored")
    func keyBeforeRead() {
        var state = AutoSpaceState()
        let generation = state.armed(.intoLatin)

        let spaced = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!spaced)
        state.read(.han, generation: generation)
        #expect(state.phase == .idle)
    }

    @Test("a read from an older switch is ignored, and cancel drops the space")
    func staleReadAndCancel() {
        var state = AutoSpaceState()
        let old = state.armed(.intoLatin)
        let current = state.armed(.intoChinese)
        state.read(.han, generation: old)
        #expect(state.phase == .reading(generation: current, direction: .intoChinese))

        state.read(.asciiLetterOrDigit, generation: current)
        state.cancel()
        let spaced = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!spaced)
    }

    @Test("no space when the character before the caret does not ask for one on this side")
    func noSpace() {
        for (direction, before) in [(AutoSpace.Direction.intoLatin, AutoSpace.Before.noSpaceNeeded), (.intoLatin, .unknown),
                                    (.intoLatin, .asciiLetterOrDigit), (.intoChinese, .han), (.intoChinese, .noSpaceNeeded)] {
            var state = AutoSpaceState()
            state.read(before, generation: state.armed(direction))
            let spaced = state.keyDown(characters: "a", commandControlOrOption: false)
            #expect(!spaced)
        }
    }

    @Test("the setting is off by default, written only when on, and survives a round trip")
    func configKey() throws {
        #expect(!SwitcherConfig.default.autoSpaceBetweenChineseAndEnglish)
        #expect(!String(decoding: try JSONEncoder().encode(SwitcherConfig.default), as: UTF8.self).contains("autoSpace"))

        var config = SwitcherConfig.default
        config.autoSpaceBetweenChineseAndEnglish = true
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.autoSpaceBetweenChineseAndEnglish)
    }
}
