import XCTest
@testable import KeyboardSwitcherCore

final class SwitcherLayoutTests: XCTestCase {
    private func arrangement(
        _ count: Int, active: Int, previous: Int? = nil, cellWidth: Double = 44
    ) -> SwitcherArrangement {
        SwitcherLayout.arrangement(slotCount: count, activeIndex: active, previousIndex: previous,
                                   maxWidth: 320, cellWidth: cellWidth, spacing: 2, padding: 5)
    }

    func testTwoSlotsAreARowWithATravellingThumb() {
        let row = arrangement(2, active: 1, previous: 0)
        XCTAssertEqual(row.variant, .row)
        XCTAssertEqual(row.columns, 2)
        XCTAssertEqual(row.items.map(\.x), [0.25, 0.75])
        XCTAssertEqual(row.items.map(\.isActive), [false, true])
        XCTAssertEqual(row.thumbStartX, 0.25)
        XCTAssertEqual(row.thumbEndX, 0.75)
        XCTAssertEqual(row.stripTravelCells, 0)
        XCTAssertFalse(row.crossfadesContent)
    }

    func testWidthBudgetDecidesBetweenRowAndCarousel() {
        XCTAssertEqual(arrangement(6, active: 0).variant, .row)
        XCTAssertEqual(arrangement(7, active: 0).variant, .carousel)
        XCTAssertEqual(arrangement(5, active: 0, cellWidth: 64).variant, .carousel)
        XCTAssertEqual(arrangement(3, active: 0, cellWidth: 400).variant, .row)
    }

    func testEightSlotsShowTheActiveSlotBetweenItsCyclicNeighbours() {
        let carousel = arrangement(8, active: 0, previous: 7)
        XCTAssertEqual(carousel.columns, 3)
        XCTAssertEqual(carousel.items.map(\.slotIndex), [6, 7, 0, 1, 2])
        let inWindow = carousel.items.filter { (0...1).contains($0.x) }
        XCTAssertEqual(inWindow.map(\.slotIndex), [7, 0, 1])
        XCTAssertEqual(inWindow.map(\.x), [1.0 / 6, 0.5, 5.0 / 6])
        XCTAssertEqual(carousel.items.filter(\.isActive).map(\.slotIndex), [0])
        XCTAssertEqual([carousel.thumbStartX, carousel.thumbEndX], [0.5, 0.5])
        XCTAssertEqual(carousel.stripTravelCells, 1)
        XCTAssertFalse(carousel.crossfadesContent)
    }

    func testCarouselTravelsTheShortWayAndCrossfadesLongJumps() {
        XCTAssertEqual(arrangement(8, active: 7, previous: 0).stripTravelCells, -1)
        let tie = arrangement(8, active: 4, previous: 0)
        XCTAssertEqual(tie.stripTravelCells, 2)
        XCTAssertTrue(tie.crossfadesContent)
        let backward = arrangement(8, active: 0, previous: 3)
        XCTAssertEqual(backward.stripTravelCells, -2)
        XCTAssertTrue(backward.crossfadesContent)
        XCTAssertFalse(arrangement(8, active: 2, previous: 0).crossfadesContent)
    }

    func testMissingOutOfRangeAndEqualPrevious() {
        for previous in [nil, -1, 8] as [Int?] {
            let carousel = arrangement(8, active: 3, previous: previous)
            XCTAssertNil(carousel.thumbStartX)
            XCTAssertEqual(carousel.stripTravelCells, 0)
            XCTAssertNil(arrangement(3, active: 1, previous: previous).thumbStartX)
        }
        let unchanged = arrangement(3, active: 1, previous: 1)
        XCTAssertEqual(unchanged.thumbStartX, unchanged.thumbEndX)
        XCTAssertEqual(arrangement(8, active: 3, previous: 3).stripTravelCells, 0)
    }

    func testZeroOneAndOutOfRangeActiveSlots() {
        let empty = arrangement(0, active: 0)
        XCTAssertEqual(empty.columns, 0)
        XCTAssertTrue(empty.items.isEmpty)

        let single = arrangement(1, active: 5)
        XCTAssertEqual(single.variant, .row)
        XCTAssertEqual(single.items, [SwitcherArrangement.Item(slotIndex: 0, x: 0.5, y: 0.5, isActive: true)])
        XCTAssertEqual(arrangement(3, active: -2).items.map(\.isActive), [true, false, false])
    }
}
