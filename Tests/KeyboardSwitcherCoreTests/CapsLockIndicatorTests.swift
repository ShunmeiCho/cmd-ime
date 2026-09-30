import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct CapsLockIndicatorTests {
    private let context = IndicatorRenderContext(isDarkAppearance: true, accentHex: "#FF2D55")
    private let sources = [
        InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
        InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin - Simplified",
                        languages: ["zh-Hans"], isSelectCapable: true),
    ]

    @Test("the first reading only seeds the state")
    func firstReadingSeeds() {
        var tracker = CapsLockTracker()

        #expect(tracker.observe(isOn: true) == nil)
        #expect(tracker.isOn == true)
    }

    @Test("a Caps Lock key event that leaves the lock as it was reports nothing")
    func unchangedReportsNothing() {
        var tracker = CapsLockTracker(isOn: false)

        #expect(tracker.observe(isOn: false) == nil)
    }

    @Test("each real toggle is reported once")
    func togglesAreReported() {
        var tracker = CapsLockTracker(isOn: false)

        #expect(tracker.observe(isOn: true) == true)
        #expect(tracker.observe(isOn: true) == nil)
        #expect(tracker.observe(isOn: false) == false)
    }

    @Test("the setting is off in old files and fresh configs, and survives a round trip")
    func configKey() throws {
        let old = Data(#"{"version": 3, "bindings": [], "inputSources": {}}"#.utf8)
        #expect(try JSONDecoder().decode(SwitcherConfig.self, from: old).showCapsLockIndicator == false)
        #expect(SwitcherConfig.default.showCapsLockIndicator == false)

        var config = SwitcherConfig.default
        config.showCapsLockIndicator = true
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.showCapsLockIndicator == true)
    }

    @Test("the bubble says what the lock did and keeps the slot's colours and source")
    func bubbleContent() throws {
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = BuiltInIndicatorThemes.legacyDefaultID
        let slotModel = try #require(IndicatorBubbleResolver.model(
            config: config, themes: BuiltInIndicatorThemes.all, sources: sources, slotID: .chinese,
            previousSlotID: nil, source: sources[1], context: context
        ))

        let on = try #require(capsLock(true, config: config, slot: .chinese))
        let off = try #require(capsLock(false, config: config, slot: .chinese))

        #expect(on.symbol == SlotSymbol(glyph: "A"))
        #expect(off.symbol == SlotSymbol(glyph: "a"))
        #expect([on.title, off.title] == ["Caps Lock On", "Caps Lock Off"])
        #expect(on.detail == "Pinyin - Simplified")
        #expect(on.tileFillHex == slotModel.tileFillHex)
        #expect(on.archetype == slotModel.archetype)
    }

    @Test("strips that draw every slot become a single bubble")
    func stripsBecomeSingle() throws {
        var switcher = SwitcherConfig.default
        switcher.switchIndicatorThemeID = BuiltInIndicatorThemes.defaultID
        let model = try #require(capsLock(true, config: switcher, slot: .chinese))

        #expect(model.archetype == .tileTwoLine)
        #expect(model.cells.isEmpty)
        #expect(IndicatorBubbleResolver.singleSlotArchetype(for: .badge) == .mark)
    }

    @Test("a source in no slot borrows the first slot's colours; no slots means no bubble")
    func fallbackSlot() throws {
        let model = try #require(capsLock(true, config: .default, slot: nil))
        #expect(model.title == "Caps Lock On")

        var empty = SwitcherConfig.default
        empty.slots = []
        #expect(capsLock(true, config: empty, slot: nil) == nil)
    }

    private func capsLock(_ isOn: Bool, config: SwitcherConfig, slot: InputRole?) -> BubbleRenderModel? {
        IndicatorBubbleResolver.capsLockModel(
            isOn: isOn, config: config, themes: BuiltInIndicatorThemes.all, sources: sources,
            slotID: slot, source: sources[1], context: context
        )
    }
}
