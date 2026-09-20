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
            XCTAssertEqual(IndicatorDisplayComposition.effective(stored, for: .badge), .iconOnly)
        }
    }

    // MARK: - Metrics

    func testDefaultGlassMetrics() {
        let metrics = BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.glass"))
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

    // MARK: - Badge

    func testBadgeIsACapsuleMeasuredFromItsGlyph() {
        let metrics = BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.badge"))
        XCTAssertEqual(metrics.baseHeight, 24)
        // The radius is capped at half the height at every factor, so the badge is a
        // pill rather than a rounded rectangle whatever the theme asks for.
        XCTAssertEqual(metrics.bubbleRadius, 12)
        XCTAssertEqual(metrics.tileSide, 0)
        XCTAssertEqual(BadgeMetrics.cellHeight(factor: 1, textFactor: 1), 18)
    }

    func testBadgeShrinksInStepWithItsGlyph() {
        // Every length is the same multiple of its base at the floor as at the top of
        // the range: the frame never runs ahead of the text.
        for factor in [BubbleMetrics.badgeMinimumFactor, 1.0, 1.3] {
            XCTAssertEqual(
                BadgeMetrics.bubbleHeight(factor: factor, textFactor: factor),
                24 * factor,
                accuracy: 0.0001
            )
        }
    }

    func testBadgeFloorsAtAReadableGlyph() {
        for requested in [0.0, SwitcherConfig.minSwitchIndicatorSizeFactor, 0.69] {
            let smallest = BubbleMetrics.effectiveFactor(requested, archetype: .badge)
            XCTAssertEqual(smallest, BubbleMetrics.badgeMinimumFactor, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(
                BadgeMetrics.glyphSize(textFactor: smallest, isDouble: false),
                BadgeMetrics.Base.minimumGlyphSize
            )
        }
        // Far below the switcher, whose floor is a name budget the badge does not have.
        XCTAssertLessThan(BubbleMetrics.badgeMinimumFactor, BubbleMetrics.switcherMinimumFactor)
    }

    func testBadgeCellBudgetsTheWidestGlyphAndItsMark() {
        func cells(_ symbols: [SlotSymbol]) -> [BubbleRenderModel.Cell] {
            symbols.map { BubbleRenderModel.Cell(symbol: $0, name: "", fillHex: "#FFFFFF", glyphHex: "#000000") }
        }
        XCTAssertEqual(BadgeMetrics.glyphUnits(for: cells([SlotSymbol(glyph: "中")])), 1.0)
        XCTAssertEqual(BadgeMetrics.glyphUnits(for: cells([SlotSymbol(glyph: "EN")])), 1.55)
        // A mark is drawn beside the glyph at a fixed ratio and is never truncated, so
        // the cell has to hold both; the widest cell sets the width for all of them.
        XCTAssertEqual(
            BadgeMetrics.glyphUnits(for: cells([SlotSymbol(glyph: "A"), SlotSymbol(glyph: "中", mark: "简")])),
            1.62,
            accuracy: 0.0001
        )
    }

    func testSizeAndTextScaleAreClampedAndMultiplied() {
        let glass = theme("builtin.glass")
        let big = SwitcherConfig.maxSwitchIndicatorSizeFactor
        let large = BubbleMetrics(sizeFactor: 9, textScale: 9, theme: glass)
        XCTAssertEqual(large.sizeFactor, big, accuracy: 0.0001)
        XCTAssertEqual(large.titleSize, 13 * big * 1.6, accuracy: 0.0001)
        XCTAssertEqual(large.tileSide, 32 * big, accuracy: 0.0001)
        XCTAssertEqual(large.shadowMargin, (44 * big).rounded(.up))
        // Larger text grows the bubble instead of clipping inside a fixed height.
        XCTAssertGreaterThan(large.baseHeight, large.tileSide + 2 * large.inset)

        let tiny = SwitcherConfig.minSwitchIndicatorSizeFactor
        let small = BubbleMetrics(sizeFactor: 0, textScale: 0, theme: glass)
        XCTAssertEqual(small.sizeFactor, tiny, accuracy: 0.0001)
        XCTAssertEqual(small.textMinWidth, 44 * tiny * 0.8, accuracy: 0.0001)
    }

    func testRadiiAreCappedConcentricOrOverridden() {
        var round = theme("builtin.line")
        round.cornerRadius = 28
        let line = BubbleMetrics(sizeFactor: 1, textScale: 1, theme: round)
        XCTAssertEqual(line.bubbleRadius, line.baseHeight / 2, accuracy: 0.0001)

        XCTAssertEqual(BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.classic")).tileRadius, 9)
        XCTAssertEqual(BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.paper-one-ink")).tileRadius, 3)
        var tight = theme("builtin.glass")
        tight.cornerRadius = 4
        XCTAssertEqual(BubbleMetrics(sizeFactor: 1, textScale: 1, theme: tight).tileRadius, 3)
    }

    func testArchetypeSpecificMetrics() {
        let paper = BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.paper-two-inks"))
        XCTAssertEqual(paper.detailSize, 10.5)
        let stacked = BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.typographic"))
        XCTAssertEqual([stacked.titleSize, stacked.detailSize, stacked.tileSide], [20, 10, 0])
        XCTAssertEqual(BubbleMetrics(sizeFactor: 1, textScale: 1, theme: theme("builtin.tile")).tileSide, 40)

        // The switcher stops shrinking where its cells would fall under their own text.
        let switcher = BubbleMetrics(sizeFactor: 0.4, textScale: 1, theme: theme("builtin.switcher"))
        XCTAssertEqual(switcher.sizeFactor, BubbleMetrics.switcherMinimumFactor, accuracy: 0.0001)
        let roomySwitcher = BubbleMetrics(sizeFactor: 1.22, textScale: 1, theme: theme("builtin.switcher"))
        XCTAssertEqual(roomySwitcher.sizeFactor, 1.22, accuracy: 0.0001)
        let largeSwitcher = BubbleMetrics(sizeFactor: 1.586, textScale: 1, theme: theme("builtin.switcher"))
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

    func testAccessibilityRectsFlipAroundThePrimaryDisplayOnly() {
        // Primary 1512 x 982; an external display sits above it (AppKit y 982...2422).
        let onPrimary = BubblePlacement.appKitRect(
            fromAccessibility: .init(x: 400, y: 300, width: 2, height: 18), primaryDisplayHeight: 982)
        XCTAssertEqual(onPrimary, .init(x: 400, y: 664, width: 2, height: 18))
        // A caret on the display above has a negative accessibility y and stays above the primary.
        let onExternal = BubblePlacement.appKitRect(
            fromAccessibility: .init(x: 400, y: -500, width: 2, height: 18), primaryDisplayHeight: 982)
        XCTAssertEqual(onExternal.y, 1464)
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
