import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct AdaptiveBubbleLayoutTests {
    private let context = IndicatorRenderContext(isDarkAppearance: true, accentHex: "#FF2D55")
    private let sources = [
        InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
        InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin - Simplified",
                        languages: ["zh-Hans"], isSelectCapable: true),
        InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", localizedName: "Hiragana",
                        languages: ["ja"], isSelectCapable: true),
    ]

    private func theme(_ id: String) throws -> IndicatorTheme {
        try #require(BuiltInIndicatorThemes.all.first { $0.id == id })
    }

    private func model(theme id: String, occasion: AdaptiveBubbleLayout.Occasion) throws -> BubbleRenderModel {
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = id
        return try #require(IndicatorBubbleResolver.model(
            config: config, themes: BuiltInIndicatorThemes.all, sources: sources, slotID: .chinese,
            previousSlotID: .english, source: sources[1], context: context, occasion: occasion
        ))
    }

    @Test("an adaptive theme draws the Mark for a switch from hidden and the Badge row otherwise")
    func policy() throws {
        let adaptive = try theme("builtin.adaptive")

        #expect(AdaptiveBubbleLayout.archetype(for: adaptive, occasion: .switched(whileVisible: false)) == .mark)
        #expect(AdaptiveBubbleLayout.archetype(for: adaptive, occasion: .switched(whileVisible: true)) == .badge)
        #expect(AdaptiveBubbleLayout.archetype(for: adaptive, occasion: .peek) == .badge)
    }

    @Test("every other theme keeps its archetype whatever the occasion", arguments: [
        "builtin.mark", "builtin.badge", "builtin.switcher", "builtin.glass",
    ])
    func otherThemesUnchanged(id: String) throws {
        let fixed = try theme(id)
        for occasion in [AdaptiveBubbleLayout.Occasion.switched(whileVisible: false), .switched(whileVisible: true), .peek] {
            #expect(AdaptiveBubbleLayout.archetype(for: fixed, occasion: occasion) == fixed.archetype)
        }
    }

    @Test("the resolver hands the view a concrete layout: a Mark alone, a Badge row with every slot")
    func resolverCoercesTheArchetype() throws {
        let compact = try model(theme: "builtin.adaptive", occasion: .switched(whileVisible: false))
        let expanded = try model(theme: "builtin.adaptive", occasion: .switched(whileVisible: true))
        let peek = try model(theme: "builtin.adaptive", occasion: .peek)

        #expect(compact.archetype == .mark)
        #expect(compact.cells.isEmpty)
        #expect(expanded.archetype == .badge)
        #expect(expanded.cells.count == SwitcherConfig.default.slots.count)
        #expect(expanded.previousIndex == 0)
        #expect(peek.archetype == .badge)
        #expect(compact.themeID == "builtin.adaptive")
        #expect(expanded.themeID == "builtin.adaptive")
    }

    @Test("the expanded row is measured as a Badge, wider than the Mark")
    func expandedIsWider() throws {
        let compact = try model(theme: "builtin.adaptive", occasion: .switched(whileVisible: false))
        let expanded = try model(theme: "builtin.adaptive", occasion: .switched(whileVisible: true))

        #expect(BadgeMetrics(model: expanded).bubbleWidth > MarkMetrics(model: compact).bubbleWidth)
    }

    @Test("the slot-colour variant expands the same way")
    func tintVariant() throws {
        #expect(try model(theme: "builtin.adaptive-tint", occasion: .switched(whileVisible: false)).archetype == .mark)
        #expect(try model(theme: "builtin.adaptive-tint", occasion: .switched(whileVisible: true)).archetype == .badge)
    }

    @Test("a Caps Lock bubble stays a single Mark in an adaptive theme")
    func capsLockStaysSingle() throws {
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = "builtin.adaptive"

        let caps = try #require(IndicatorBubbleResolver.capsLockModel(
            isOn: true, config: config, themes: BuiltInIndicatorThemes.all, sources: sources,
            slotID: .chinese, source: sources[1], context: context
        ))

        #expect(caps.archetype == .mark)
        #expect(caps.cells.isEmpty)
    }

    @Test("the flag survives a theme file round trip, and older files read without it")
    func codec() throws {
        var duplicated = try theme("builtin.adaptive")
        duplicated.id = "adaptive-copy"

        let data = try JSONEncoder().encode(duplicated)
        let decoded = try IndicatorTheme.decoding(data, fileName: "adaptive-copy.json").get()
        let plain = try IndicatorTheme.decoding(
            Data(#"{"schemaVersion": 1, "id": "plain", "archetype": "mark"}"#.utf8), fileName: "plain.json"
        ).get()

        #expect(decoded.isAdaptive)
        #expect(decoded == duplicated)
        #expect(!plain.isAdaptive)
    }

    @Test("the flag means nothing outside a Mark, and is not written for one")
    func flagNeedsTheMark() throws {
        var theme = try theme("builtin.adaptive")
        theme.id = "switched-away"
        theme.archetype = .tileTwoLine

        let json = String(decoding: try JSONEncoder().encode(theme), as: UTF8.self)

        #expect(!theme.isAdaptive)
        #expect(AdaptiveBubbleLayout.archetype(for: theme, occasion: .peek) == .tileTwoLine)
        #expect(!json.contains("expandsWhileSwitching"))
    }
}
