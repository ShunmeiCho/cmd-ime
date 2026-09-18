import XCTest
@testable import KeyboardSwitcherCore

final class SlotBoardGeometryTests: XCTestCase {
    func testEmptyListAlwaysReturnsZero() {
        for probe in [-100.0, 20, 500] {
            XCTAssertEqual(SlotBoardGeometry.insertionIndex(
                probeY: probe, top: 20, restingHeights: [], spacing: 9, placeholderHeight: 60
            ), 0)
        }
    }

    func testPositionsOutsideCardsChooseFirstAndLastGaps() {
        let heights = [40.0, 70, 30]
        XCTAssertEqual(SlotBoardGeometry.insertionIndex(
            probeY: -100, top: 20, restingHeights: heights, spacing: 9, placeholderHeight: 50
        ), 0)
        XCTAssertEqual(SlotBoardGeometry.insertionIndex(
            probeY: 500, top: 20, restingHeights: heights, spacing: 9, placeholderHeight: 50
        ), heights.count)
    }

    func testEqualHeightBoundariesPreferLowerIndexOnTies() {
        // Gap centres are 30, 80, 130, 180; boundaries are their midpoints.
        for (lowerIndex, boundary) in [55.0, 105, 155].enumerated() {
            for (probe, expected) in [(boundary.nextDown, lowerIndex),
                                      (boundary, lowerIndex),
                                      (boundary.nextUp, lowerIndex + 1)] {
                XCTAssertEqual(SlotBoardGeometry.insertionIndex(
                    probeY: probe, top: 10, restingHeights: [40, 40, 40], spacing: 10, placeholderHeight: 40
                ), expected, "probeY=\(probe)")
            }
        }
    }

    func testUnequalHeightBoundariesPreferLowerIndexOnTies() {
        // Gap centres are 40, 80, 160, 190, not uniformly spaced.
        for (lowerIndex, boundary) in [60.0, 120, 175].enumerated() {
            for (probe, expected) in [(boundary.nextDown, lowerIndex),
                                      (boundary, lowerIndex),
                                      (boundary.nextUp, lowerIndex + 1)] {
                XCTAssertEqual(SlotBoardGeometry.insertionIndex(
                    probeY: probe, top: 20, restingHeights: [30, 70, 20], spacing: 10, placeholderHeight: 40
                ), expected, "probeY=\(probe)")
            }
        }
    }

    func testInsertionIndexIsMonotonicOverProbeSweep() {
        let heights = [35.0, 80, 25, 60]
        var previous = 0
        var visited: Set<Int> = []
        for probe in stride(from: -100.0, through: 500.0, by: 0.5) {
            let index = SlotBoardGeometry.insertionIndex(
                probeY: probe, top: 20, restingHeights: heights, spacing: 9, placeholderHeight: 55
            )
            XCTAssertGreaterThanOrEqual(index, previous, "probeY=\(probe)")
            XCTAssertTrue((0...heights.count).contains(index))
            visited.insert(index)
            previous = index
        }
        XCTAssertEqual(visited, Set(0...heights.count))
    }

    func testPlaceholderHeightMovesGapCentresIndependentlyOfCardHeights() {
        // At probe 60, a 20-point placeholder puts the first boundary at 35;
        // a 100-point placeholder puts it at 75, with the same resting cards.
        XCTAssertEqual(SlotBoardGeometry.insertionIndex(
            probeY: 60, top: 0, restingHeights: [40, 40], spacing: 10, placeholderHeight: 20
        ), 1)
        XCTAssertEqual(SlotBoardGeometry.insertionIndex(
            probeY: 60, top: 0, restingHeights: [40, 40], spacing: 10, placeholderHeight: 100
        ), 0)
    }

    func testPlaceholderMinYUsesTopAndPrecedingHeightsPlusSpacing() {
        for (index, expected) in [(-1, 12.5), (0, 12.5), (1, 47.5), (2, 122.5), (3, 147.5), (10, 147.5)] {
            XCTAssertEqual(SlotBoardGeometry.placeholderMinY(
                at: index, top: 12.5, restingHeights: [30, 70, 20], spacing: 5
            ), expected)
        }
        XCTAssertEqual(SlotBoardGeometry.placeholderMinY(
            at: 0, top: 12.5, restingHeights: [], spacing: 5
        ), 12.5)
    }

    func testInsertionLineGapMapsFinalIndexBackToUnchangedOrder() {
        // In [A, B, C, D], moving B down to index 2 points after C (gap 3),
        // while moving C up to index 1 points before B (gap 1).
        XCTAssertEqual(SlotBoardGeometry.insertionLineGap(finalIndex: 2, sourceIndex: 1), 3)
        XCTAssertEqual(SlotBoardGeometry.insertionLineGap(finalIndex: 1, sourceIndex: 2), 1)
        XCTAssertEqual(SlotBoardGeometry.insertionLineGap(finalIndex: 3, sourceIndex: 0), 4)
        XCTAssertEqual(SlotBoardGeometry.insertionLineGap(finalIndex: 0, sourceIndex: 3), 0)
        XCTAssertNil(SlotBoardGeometry.insertionLineGap(finalIndex: 0, sourceIndex: 0))
        XCTAssertNil(SlotBoardGeometry.insertionLineGap(finalIndex: 2, sourceIndex: 2))
    }
}
