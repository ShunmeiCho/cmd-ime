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
        #expect(CaretNeighbor.caret(before: .found(before), after: .none) == .init(x: 114, y: 40, width: 0, height: 18))
        #expect(CaretNeighbor.caret(before: .none, after: .found(after)) == .init(x: 114, y: 40, width: 0, height: 18))
        #expect(CaretNeighbor.caret(before: .found(before), after: .found(after)) == .init(x: 114, y: 40, width: 0, height: 18))
    }

    @Test("a soft wrap, right-to-left or unknown text, or an unknown side give no caret")
    func undecidable() {
        let endOfLine = CaretNeighbor.Neighbor(rect: .init(x: 180, y: 20, width: 10, height: 18), text: "a")
        let startOfNext = CaretNeighbor.Neighbor(rect: .init(x: 0, y: 38, width: 10, height: 18), text: "b")
        #expect(CaretNeighbor.caret(before: .found(endOfLine), after: .found(startOfNext)) == nil)
        #expect(CaretNeighbor.caret(before: .found(endOfLine), after: .unknown) == nil)
        #expect(CaretNeighbor.caret(before: .found(.init(rect: character, text: "ש")), after: .none) == nil)
        #expect(CaretNeighbor.caret(before: .none, after: .found(.init(rect: character, text: "ع"))) == nil)
        #expect(CaretNeighbor.caret(before: .found(.init(rect: character, text: nil)), after: .none) == nil)
        #expect(CaretNeighbor.caret(before: .none, after: .none) == nil)
    }

    @Test("an empty short field puts the caret at its leading edge, centred; a tall editor gives none")
    func field() {
        #expect(CaretNeighbor.caret(inField: .init(x: 300, y: 330, width: 600, height: 50)) == .init(x: 300, y: 346, width: 0, height: 18))
        #expect(CaretNeighbor.caret(inField: .init(x: 0, y: 0, width: 800, height: 600)) == nil)
        #expect(CaretNeighbor.caret(inField: .init(x: 0, y: 0, width: 0, height: 0)) == nil)
    }

    @Test("a text marker caret is the zero-width rect inside text, or the leading edge of an empty line's box (Slack)")
    func textMarkerCaret() {
        #expect(CaretNeighbor.caret(fromTextMarkerBounds: .init(x: 489, y: 915, width: 0, height: 18)) == .init(x: 489, y: 915, width: 0, height: 18))
        #expect(CaretNeighbor.caret(fromTextMarkerBounds: .init(x: 440, y: 913, width: 671, height: 22)) == .init(x: 440, y: 913, width: 0, height: 22))
        #expect(CaretNeighbor.caret(fromTextMarkerBounds: .init(x: 0, y: 1112, width: 0, height: 0)) == nil)
        #expect(CaretNeighbor.caret(fromTextMarkerBounds: .init(x: 0, y: 0, width: 800, height: 600)) == nil)
    }

    @Test("only whitespace counts as blank; unknown text does not")
    func blank() {
        #expect(CaretNeighbor.isBlank("\n"))
        #expect(CaretNeighbor.isBlank(" \n"))
        #expect(!CaretNeighbor.isBlank("a\n"))
        #expect(!CaretNeighbor.isBlank(nil))
    }
}
