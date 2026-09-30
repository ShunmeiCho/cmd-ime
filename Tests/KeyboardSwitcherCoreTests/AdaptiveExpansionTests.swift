import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct AdaptiveExpansionTests {
    private let compact = AdaptiveExpansion.Size(width: 28, height: 28)
    private let expanded = AdaptiveExpansion.Size(width: 102, height: 24)

    @Test("the spring starts at rest, rises without overshoot and settles near one")
    func springIsCriticallyDamped() {
        #expect(AdaptiveExpansion.progress(at: 0) == 0)
        var previous = 0.0
        for step in 1...60 {
            let value = AdaptiveExpansion.progress(at: Double(step) / 120)
            #expect(value >= previous)
            #expect(value <= 1)
            previous = value
        }
        let settle = AdaptiveExpansion.settleTime()
        #expect(1 - AdaptiveExpansion.progress(at: settle) <= AdaptiveExpansion.settleThreshold + 1e-9)
        #expect(settle < 0.35)
    }

    @Test("the Mark's own glyph is there from the start; the others arrive further out, later")
    func revealIsStaggeredByDistance() {
        #expect(AdaptiveExpansion.reveal(at: 0, distance: 0) == 1)
        #expect(AdaptiveExpansion.reveal(at: 0, distance: 1) == 0)
        let midway = 0.06
        #expect(AdaptiveExpansion.reveal(at: midway, distance: 1) > AdaptiveExpansion.reveal(at: midway, distance: 2))
        #expect(AdaptiveExpansion.reveal(at: AdaptiveExpansion.revealDuration, distance: 1) == 1)
        #expect(AdaptiveExpansion.revealScale(0) == AdaptiveExpansion.revealStartScale)
        #expect(AdaptiveExpansion.revealScale(1) == 1)
    }

    @Test("it finishes only after the spring settles and the furthest glyph arrives")
    func finishWaitsForTheLastGlyph() {
        let lastReveal = 3 * AdaptiveExpansion.staggerDelay + AdaptiveExpansion.revealDuration
        let end = max(AdaptiveExpansion.settleTime(), lastReveal)
        #expect(!AdaptiveExpansion.isFinished(at: end - 0.001, maxDistance: 4))
        #expect(AdaptiveExpansion.isFinished(at: end, maxDistance: 4))
    }

    @Test("the panel keeps room for either layout, so growing never resizes it")
    func reservedAreaCoversBothLayouts() {
        let reserved = AdaptiveExpansion.reservedSize(compact: compact, expanded: expanded)

        #expect(reserved == AdaptiveExpansion.Size(width: 102, height: 28))
    }

    @Test("the pill grows between the two sizes and keeps the edge nearest the caret")
    func pillGeometry() {
        let reserved = AdaptiveExpansion.reservedSize(compact: compact, expanded: expanded)
        let half = AdaptiveExpansion.pillSize(compact: compact, expanded: expanded, progress: 0.5)

        #expect(half == AdaptiveExpansion.Size(width: 65, height: 26))
        #expect(AdaptiveExpansion.pillSize(compact: compact, expanded: expanded, progress: 1) == expanded)
        let above = AdaptiveExpansion.pillOrigin(pill: half, reserved: reserved, anchor: .bottomLeading)
        let below = AdaptiveExpansion.pillOrigin(pill: half, reserved: reserved, anchor: .topLeading)
        #expect(above.x == 0 && above.y == 0)
        #expect(below.x == 0 && below.y == 2)
    }

    @Test("the row starts with the Mark's glyph where the Mark drew it and ends in its own cell")
    func rowSlidesFromTheMark() {
        #expect(AdaptiveExpansion.rowOffset(progress: 0, markGlyphCenter: 14, cellCenter: 60) == -46)
        #expect(AdaptiveExpansion.rowOffset(progress: 1, markGlyphCenter: 14, cellCenter: 60) == 0)
    }

    @Test("a row badge names each cell's centre; a carousel has none")
    func badgeCellCentres() throws {
        let sources = [
            InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
            InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin - Simplified",
                            languages: ["zh-Hans"], isSelectCapable: true),
        ]
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = "builtin.adaptive"
        let model = try #require(IndicatorBubbleResolver.model(
            config: config, themes: BuiltInIndicatorThemes.all, sources: sources, slotID: .chinese,
            previousSlotID: .english, source: sources[1],
            context: IndicatorRenderContext(isDarkAppearance: true, accentHex: "#FF2D55"), occasion: .peek
        ))
        let metrics = BadgeMetrics(model: model)
        try #require(metrics.arrangement.variant == .row)

        let first = try #require(AdaptiveExpansion.badgeCellCenter(metrics, slotIndex: 0))
        let second = try #require(AdaptiveExpansion.badgeCellCenter(metrics, slotIndex: 1))
        #expect(first == metrics.padding + metrics.cellWidth / 2)
        #expect(second - first == metrics.step)
        #expect(AdaptiveExpansion.badgeCellCenter(metrics, slotIndex: 99) == nil)
    }
}
