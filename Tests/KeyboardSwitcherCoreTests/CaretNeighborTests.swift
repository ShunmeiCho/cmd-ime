import Testing
@testable import KeyboardSwitcherCore

struct CaretNeighborTests {
    private let character = CaretNeighbor.Rect(x: 100, y: 40, width: 14, height: 18)

    @Test("the character before the caret and the one after are asked; at the start only the one after")
    func candidates() {
        #expect(CaretNeighbor.candidates(caretLocation: 5) == [.init(location: 4, side: .before), .init(location: 5, side: .after)])
        #expect(CaretNeighbor.candidates(caretLocation: 0) == [.init(location: 0, side: .after)])
    }

    @Test("the caret sits at the trailing edge of the character before it and the leading edge of the one after")
    func caret() {
        let before = CaretNeighbor.Neighbor(rect: character, text: "中")
        let after = CaretNeighbor.Neighbor(rect: .init(x: 114, y: 40, width: 8, height: 18), text: "a")
        #expect(CaretNeighbor.caret(before: before, after: nil) == .init(x: 114, y: 40, width: 0, height: 18))
        #expect(CaretNeighbor.caret(before: nil, after: after) == .init(x: 114, y: 40, width: 0, height: 18))
        #expect(CaretNeighbor.caret(before: before, after: after) == .init(x: 114, y: 40, width: 0, height: 18))
    }

    @Test("neighbors on two lines (a soft wrap) or right-to-left text give no caret")
    func undecidable() {
        let endOfLine = CaretNeighbor.Neighbor(rect: .init(x: 180, y: 20, width: 10, height: 18), text: "a")
        let startOfNext = CaretNeighbor.Neighbor(rect: .init(x: 0, y: 38, width: 10, height: 18), text: "b")
        #expect(CaretNeighbor.caret(before: endOfLine, after: startOfNext) == nil)
        #expect(CaretNeighbor.caret(before: .init(rect: character, text: "ש"), after: nil) == nil)
        #expect(CaretNeighbor.caret(before: nil, after: .init(rect: character, text: "ع")) == nil)
        #expect(CaretNeighbor.caret(before: nil, after: nil) == nil)
    }
}
