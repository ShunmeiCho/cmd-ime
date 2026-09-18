import XCTest
@testable import KeyboardSwitcherCore

final class BubbleLayoutTests: XCTestCase {
    private func theme(_ id: String) -> IndicatorTheme {
        BuiltInIndicatorThemes.all.first { $0.id == id }!
    }

    // MARK: - Display composition

    func testDisplayComposesWithEveryArchetype() {
        let all: [SwitchIndicatorContentStyle] = [.iconAndText, .iconOnly, .textOnly]
        for archetype in [BubbleArchetype.tileTwoLine, .lineWithBar, .switcher] {
            XCTAssertEqual(IndicatorDisplayComposition.supported(archetype), all)
            for stored in all {
                XCTAssertEqual(IndicatorDisplayComposition.effective(stored, for: archetype), stored)
            }
        }
        for stored in all {
            XCTAssertEqual(IndicatorDisplayComposition.effective(stored, for: .stackedText), .textOnly)
            XCTAssertEqual(IndicatorDisplayComposition.effective(stored, for: .tileOnly), .iconOnly)
        }
    }

    // MARK: - Metrics

    func testDefaultGlassMetrics() {
        let metrics = BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.glass"))
        XCTAssertEqual(metrics.sizeFactor, 1)
        XCTAssertEqual([metrics.inset, metrics.tileSide, metrics.gap, metrics.trailingPadding], [9, 32, 10, 15])
        XCTAssertEqual(metrics.baseHeight, 50)
        XCTAssertEqual([metrics.bubbleRadius, metrics.tileRadius], [16, 7])
        XCTAssertEqual([metrics.titleSize, metrics.detailSize], [13, 11])
        XCTAssertEqual(metrics.titleLineHeight, 16.25, accuracy: 0.0001)
        XCTAssertEqual(metrics.detailLineHeight, 14.3, accuracy: 0.0001)
        XCTAssertEqual([metrics.textMinWidth, metrics.textMaxWidth, metrics.maxBubbleWidth], [44, 168, 320])
        XCTAssertEqual(metrics.shadowMargin, 44)
    }

    func testSizeScaleAndTextScaleAreClampedAndMultiplied() {
        let glass = theme("builtin.glass")
        let large = BubbleMetrics(size: .large, scale: 9, textScale: 9, theme: glass)
        XCTAssertEqual(large.sizeFactor, 1.22 * 1.3, accuracy: 0.0001)
        XCTAssertEqual(large.titleSize, 13 * 1.22 * 1.3 * 1.6, accuracy: 0.0001)
        XCTAssertEqual(large.tileSide, 32 * 1.22 * 1.3, accuracy: 0.0001)
        XCTAssertEqual(large.shadowMargin, (44 * 1.22 * 1.3).rounded(.up))
        // Larger text grows the bubble instead of clipping inside a fixed height.
        XCTAssertGreaterThan(large.baseHeight, large.tileSide + 2 * large.inset)

        let small = BubbleMetrics(size: .small, scale: 0, textScale: 0, theme: glass)
        XCTAssertEqual(small.sizeFactor, 0.82 * BubbleMetrics.minimumScaleOutsideSwitcher, accuracy: 0.0001)
        XCTAssertEqual(small.textMinWidth, 44 * 0.82 * BubbleMetrics.minimumScaleOutsideSwitcher * 0.8, accuracy: 0.0001)
    }

    func testRadiiAreCappedConcentricOrOverridden() {
        var round = theme("builtin.line")
        round.cornerRadius = 28
        let line = BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: round)
        XCTAssertEqual(line.bubbleRadius, line.baseHeight / 2, accuracy: 0.0001)

        XCTAssertEqual(BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.classic")).tileRadius, 9)
        XCTAssertEqual(BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.paper-one-ink")).tileRadius, 3)
        var tight = theme("builtin.glass")
        tight.cornerRadius = 4
        XCTAssertEqual(BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: tight).tileRadius, 3)
    }

    func testArchetypeSpecificMetrics() {
        let paper = BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.paper-two-inks"))
        XCTAssertEqual(paper.detailSize, 10.5)
        let stacked = BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.typographic"))
        XCTAssertEqual([stacked.titleSize, stacked.detailSize, stacked.tileSide], [20, 10, 0])
        XCTAssertEqual(BubbleMetrics(size: .medium, scale: 1, textScale: 1, theme: theme("builtin.tile")).tileSide, 40)

        // Only the switcher follows Scale below 40%.
        let switcher = BubbleMetrics(size: .small, scale: 0.25, textScale: 1, theme: theme("builtin.switcher"))
        XCTAssertEqual(switcher.sizeFactor, 0.82 * 0.25, accuracy: 0.0001)
        let tile = BubbleMetrics(size: .small, scale: 0.25, textScale: 1, theme: theme("builtin.tile"))
        XCTAssertEqual(tile.sizeFactor, 0.82 * BubbleMetrics.minimumScaleOutsideSwitcher, accuracy: 0.0001)
        let largeSwitcher = BubbleMetrics(size: .large, scale: 1.3, textScale: 1, theme: theme("builtin.switcher"))
        XCTAssertEqual(largeSwitcher.maxBubbleWidth, 320)
    }

    // MARK: - Placement

    private let screen = BubblePlacement.Rect(x: 0, y: 0, width: 1440, height: 900)

    func testPreferredSpotIsAboveAndRightOfTheCaret() {
        let caret = BubblePlacement.Rect(x: 400, y: 300, width: 2, height: 20)
        let placement = BubblePlacement.resolve(caret: caret, pointerX: 0, pointerY: 0,
                                                bubbleWidth: 150, bubbleHeight: 50, visible: screen)
        XCTAssertEqual(placement, BubblePlacement(originX: 411, originY: 338, anchor: .bottomLeading))
    }

    func testFlipsBelowTheCaretNearTheTopEdge() {
        let caret = BubblePlacement.Rect(x: 400, y: 860, width: 2, height: 20)
        let placement = BubblePlacement.resolve(caret: caret, pointerX: 0, pointerY: 0,
                                                bubbleWidth: 150, bubbleHeight: 50, visible: screen)
        XCTAssertEqual(placement, BubblePlacement(originX: 411, originY: 860 - 18 - 50, anchor: .topLeading))
    }

    func testClampsToTheVisibleFrameAndFallsBackToThePointer() {
        let caret = BubblePlacement.Rect(x: 1430, y: 300, width: 2, height: 20)
        let clamped = BubblePlacement.resolve(caret: caret, pointerX: 0, pointerY: 0,
                                              bubbleWidth: 150, bubbleHeight: 50, visible: screen)
        XCTAssertEqual(clamped.originX, 1440 - 8 - 150)

        let offset = BubblePlacement.Rect(x: -1440, y: 100, width: 1440, height: 900)
        let pointer = BubblePlacement.resolve(caret: nil, pointerX: -2000, pointerY: 500,
                                              bubbleWidth: 150, bubbleHeight: 50, visible: offset)
        XCTAssertEqual(pointer, BubblePlacement(originX: -1432, originY: 518, anchor: .bottomLeading))
    }

    func testAResizedBubbleKeepsItsAnchorCornerAndStaysOnScreen() {
        let old = BubblePlacement.Rect(x: 400, y: 300, width: 120, height: 50)
        XCTAssertEqual(
            BubblePlacement.resized(from: old, anchor: .bottomLeading, width: 200, height: 60, visible: screen),
            BubblePlacement.Rect(x: 400, y: 300, width: 200, height: 60)
        )
        XCTAssertEqual(
            BubblePlacement.resized(from: old, anchor: .topLeading, width: 200, height: 60, visible: screen),
            BubblePlacement.Rect(x: 400, y: 290, width: 200, height: 60)
        )

        let atTheEdge = BubblePlacement.Rect(x: 1440 - 8 - 120, y: 12, width: 120, height: 50)
        XCTAssertEqual(
            BubblePlacement.resized(from: atTheEdge, anchor: .topLeading, width: 200, height: 60, visible: screen),
            BubblePlacement.Rect(x: 1440 - 8 - 200, y: 8, width: 200, height: 60)
        )
    }
}
