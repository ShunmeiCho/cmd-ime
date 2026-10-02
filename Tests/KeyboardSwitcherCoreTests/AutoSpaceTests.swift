import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct AutoSpaceTests {
    @Test("only a Han character asks for a space", arguments: [
        ("中", AutoSpace.Before.han), ("文字", .han), ("𠀀", .han),
        (" ", .noSpaceNeeded), ("，", .noSpaceNeeded), ("。", .noSpaceNeeded), ("a", .noSpaceNeeded),
        ("1", .noSpaceNeeded), ("あ", .noSpaceNeeded), ("\n", .noSpaceNeeded),
    ])
    func classify(text: String, expected: AutoSpace.Before) {
        #expect(AutoSpace.classify(text) == expected)
    }

    @Test("nothing read is unknown")
    func unknown() {
        #expect(AutoSpace.classify(nil) == .unknown)
        #expect(AutoSpace.classify("") == .unknown)
    }

    @Test("a Latin source arms, a CJK input method does not")
    func arms() {
        let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true)
        let pinyin = InputSourceInfo(id: "p", localizedName: "Pinyin", languages: ["zh-Hans"], isSelectCapable: true)
        let kana = InputSourceInfo(id: "k", localizedName: "Kana", languages: ["ja"], isSelectCapable: true)
        #expect(AutoSpace.arms(switchingTo: abc))
        #expect(!AutoSpace.arms(switchingTo: pinyin))
        #expect(!AutoSpace.arms(switchingTo: kana))
    }

    @Test("ASCII letters and digits qualify; punctuation, space and shortcuts do not")
    func qualifies() {
        #expect(AutoSpace.qualifies(characters: "a", commandControlOrOption: false))
        #expect(AutoSpace.qualifies(characters: "Z", commandControlOrOption: false))
        #expect(AutoSpace.qualifies(characters: "7", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(characters: "a", commandControlOrOption: true))
        #expect(!AutoSpace.qualifies(characters: " ", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(characters: "(", commandControlOrOption: false))
        #expect(!AutoSpace.qualifies(characters: "", commandControlOrOption: false))
    }

    @Test("after Han, the first letter gets a space and the second does not")
    func spendsOnce() {
        var state = AutoSpaceState()
        let generation = state.armed()
        state.read(.han, generation: generation)

        let spaced1 = state.keyDown(characters: "E", commandControlOrOption: false)
        #expect(spaced1)
        let spaced2 = state.keyDown(characters: "n", commandControlOrOption: false)
        #expect(!spaced2)
    }

    @Test("a first key that does not qualify ends the chance")
    func otherKeyEnds() {
        var state = AutoSpaceState()
        let generation = state.armed()
        state.read(.han, generation: generation)

        let spaced3 = state.keyDown(characters: " ", commandControlOrOption: false)
        #expect(!spaced3)
        let spaced4 = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!spaced4)
    }

    @Test("a key typed before the read finishes passes, and the late read is ignored")
    func keyBeforeRead() {
        var state = AutoSpaceState()
        let generation = state.armed()

        let spaced5 = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!spaced5)
        state.read(.han, generation: generation)
        #expect(state.phase == .idle)
    }

    @Test("a read from an older switch is ignored, and cancel drops the space")
    func staleReadAndCancel() {
        var state = AutoSpaceState()
        let old = state.armed()
        let current = state.armed()
        state.read(.han, generation: old)
        #expect(state.phase == .reading(generation: current))

        state.read(.han, generation: current)
        state.cancel()
        let spaced6 = state.keyDown(characters: "a", commandControlOrOption: false)
        #expect(!spaced6)
    }

    @Test("no space after a space, punctuation or an unreadable caret")
    func noSpace() {
        for before in [AutoSpace.Before.noSpaceNeeded, .unknown] {
            var state = AutoSpaceState()
            let generation = state.armed()
            state.read(before, generation: generation)
            let spaced7 = state.keyDown(characters: "a", commandControlOrOption: false)
            #expect(!spaced7)
        }
    }

    @Test("the setting is off by default, written only when on, and survives a round trip")
    func configKey() throws {
        #expect(!SwitcherConfig.default.autoSpaceAfterHan)
        #expect(!String(decoding: try JSONEncoder().encode(SwitcherConfig.default), as: UTF8.self).contains("autoSpaceAfterHan"))

        var config = SwitcherConfig.default
        config.autoSpaceAfterHan = true
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.autoSpaceAfterHan)
    }
}
