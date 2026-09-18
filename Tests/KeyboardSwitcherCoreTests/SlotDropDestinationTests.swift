import XCTest
@testable import KeyboardSwitcherCore

final class SlotDropDestinationTests: XCTestCase {
    private let ko = InputRole(rawValue: "korean")
    private let extra = InputRole(rawValue: "extra")

    func testDeletionBeforeDestinationRebasesFinalIndex() {
        XCTAssertEqual(resolve(current: [.english, .japanese, ko]), 1)
    }

    func testUnchangedOrderPreservesEveryGap() {
        let order: [InputRole] = [.english, .chinese, .japanese, ko]
        for dragged in order {
            let remaining = order.filter { $0 != dragged }
            for index in 0...remaining.count {
                XCTAssertEqual(SlotDropDestination.finalIndex(
                    originalOrder: order, draggedID: dragged,
                    previousNeighbor: index > 0 ? remaining[index - 1] : nil,
                    nextNeighbor: index < remaining.count ? remaining[index] : nil,
                    currentOrder: order
                ), index)
            }
        }
    }

    func testNonstructuralChangesNeedNoRevisionCheck() {
        XCTAssertEqual(resolve(current: [.english, .chinese, .japanese, ko]), 2)
    }

    func testDraggedPositionIsExcludedFromComparison() {
        XCTAssertEqual(resolve(current: [.chinese, .japanese, ko, .english]), 2)
    }

    func testOneSurvivingNeighborAnchorsDestination() {
        XCTAssertEqual(resolve(current: [.english, .chinese, .japanese, extra]), 2)
        XCTAssertEqual(resolve(current: [.english, .chinese, extra, ko]), 2)
    }

    func testInsertedSlotsBetweenNeighborsPreferBeforeNext() {
        XCTAssertEqual(resolve(current: [.english, .chinese, .japanese, extra, ko]), 3)
    }

    func testReversedSurvivingNeighborsRejectDestination() {
        XCTAssertNil(resolve(current: [.english, .chinese, ko, .japanese]))
    }

    func testBothMissingNeighborsRejectEvenIfRemainingListIsEmpty() {
        XCTAssertNil(resolve(current: [.english, .chinese]))
        XCTAssertNil(resolve(current: [.english]))
    }

    func testRemovedOrUnknownDraggedSlotRejectsDestination() {
        XCTAssertNil(resolve(current: [.chinese, .japanese, ko]))
        XCTAssertNil(SlotDropDestination.finalIndex(
            originalOrder: [.chinese], draggedID: .english,
            previousNeighbor: nil, nextNeighbor: .chinese,
            currentOrder: [.english, .chinese]
        ))
    }

    func testSourceAdditionAtEveryOriginalGap() {
        let order: [InputRole] = [.english, .chinese]
        for index in 0...order.count {
            XCTAssertEqual(SlotDropDestination.finalIndex(
                originalOrder: order, draggedID: nil,
                previousNeighbor: index > 0 ? order[index - 1] : nil,
                nextNeighbor: index < order.count ? order[index] : nil,
                currentOrder: order
            ), index)
        }
        XCTAssertEqual(SlotDropDestination.finalIndex(
            originalOrder: [.english, .chinese], draggedID: nil,
            previousNeighbor: .english, nextNeighbor: .chinese,
            currentOrder: [.chinese]
        ), 0)
    }

    func testEdgesFollowSurvivingAnchorRatherThanNewBoundary() {
        XCTAssertEqual(SlotDropDestination.finalIndex(
            originalOrder: [.english, .chinese], draggedID: nil,
            previousNeighbor: nil, nextNeighbor: .english,
            currentOrder: [extra, .english, .chinese]
        ), 1)
        XCTAssertEqual(SlotDropDestination.finalIndex(
            originalOrder: [.english, .chinese], draggedID: nil,
            previousNeighbor: .chinese, nextNeighbor: nil,
            currentOrder: [.english, .chinese, extra]
        ), 2)
        XCTAssertNil(SlotDropDestination.finalIndex(
            originalOrder: [.english, .chinese], draggedID: nil,
            previousNeighbor: nil, nextNeighbor: .english,
            currentOrder: [.chinese]
        ))
    }

    func testEmptyOriginalGapOnlyWorksWhileRemainingOrderIsUnchanged() {
        for dragged: InputRole? in [nil, .english] {
            let order: [InputRole] = dragged.map { [$0] } ?? []
            XCTAssertEqual(SlotDropDestination.finalIndex(
                originalOrder: order, draggedID: dragged,
                previousNeighbor: nil, nextNeighbor: nil, currentOrder: order
            ), 0)
            XCTAssertNil(SlotDropDestination.finalIndex(
                originalOrder: order, draggedID: dragged,
                previousNeighbor: nil, nextNeighbor: nil, currentOrder: order + [extra]
            ))
        }
    }

    func testInvalidOriginalNeighborsAreRejected() {
        let order: [InputRole] = [.english, .chinese, .japanese, ko]
        let invalid: [(InputRole?, InputRole?)] = [
            (nil, nil), (nil, .japanese), (.chinese, nil),
            (.chinese, ko), (ko, .japanese), (.japanese, .japanese),
            (.english, .chinese), (extra, .chinese)
        ]
        for (previous, next) in invalid {
            for current in [order, order + [extra]] {
                XCTAssertNil(SlotDropDestination.finalIndex(
                    originalOrder: order, draggedID: .english,
                    previousNeighbor: previous, nextNeighbor: next, currentOrder: current
                ))
            }
        }
    }

    private func resolve(current: [InputRole]) -> Int? {
        SlotDropDestination.finalIndex(
            originalOrder: [.english, .chinese, .japanese, ko], draggedID: .english,
            previousNeighbor: .japanese, nextNeighbor: ko, currentOrder: current
        )
    }
}
