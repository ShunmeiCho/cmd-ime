import Testing
@testable import KeyboardSwitcherCore

struct CaretNeighborTests {
    @Test("the character before the caret is asked first, then the one after; at the start only the one after")
    func candidates() {
        #expect(CaretNeighbor.candidates(caretLocation: 5) == [.init(location: 4, side: .before), .init(location: 5, side: .after)])
        #expect(CaretNeighbor.candidates(caretLocation: 0) == [.init(location: 0, side: .after)])
    }

    @Test("the caret sits at the trailing edge of the character before it and the leading edge of the one after")
    func caret() {
        let character = CaretNeighbor.Rect(x: 100, y: 40, width: 14, height: 18)
        #expect(CaretNeighbor.caret(fromCharacter: character, side: .before) == .init(x: 114, y: 40, width: 0, height: 18))
        #expect(CaretNeighbor.caret(fromCharacter: character, side: .after) == .init(x: 100, y: 40, width: 0, height: 18))
    }
}
