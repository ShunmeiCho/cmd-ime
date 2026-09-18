import XCTest
@testable import KeyboardSwitcherCore

final class BubbleRenderModelTests: XCTestCase {
    private let dark = IndicatorRenderContext(isDarkAppearance: true, accentHex: "#FF2D55")
    private let sources = [
        InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
        InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "Pinyin - Simplified",
                        languages: ["zh-Hans"], isSelectCapable: true),
        InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", localizedName: "Hiragana",
                        languages: ["ja"], isSelectCapable: true),
    ]

    private func model(
        _ config: SwitcherConfig = .default,
        slot: InputRole = .chinese,
        previous: InputRole? = nil,
        context: IndicatorRenderContext? = nil
    ) throws -> BubbleRenderModel {
        try XCTUnwrap(IndicatorBubbleResolver.model(
            config: config, themes: BuiltInIndicatorThemes.all, sources: sources, slotID: slot,
            previousSlotID: previous, source: InputSourceMatcher.bestMatch(for: slot, sources: sources, config: config),
            context: context ?? dark
        ))
    }

    private func config(theme: String?, _ edit: (inout SwitcherConfig) -> Void = { _ in }) -> SwitcherConfig {
        var config = SwitcherConfig.default
        config.switchIndicatorThemeID = theme
        edit(&config)
        return config
    }

    func testConfigWithoutAThemeRendersGlassWithTheStoredSettings() throws {
        let legacy = config(theme: nil) {
            $0.switchIndicatorSize = .large
            $0.switchIndicatorScale = 1.2
            $0.switchIndicatorContentStyle = .iconOnly
        }
        let model = try model(legacy)

        XCTAssertEqual(model.themeID, "builtin.glass")
        XCTAssertNil(model.fellBackFromThemeID)
        XCTAssertEqual(model.display, .iconOnly)
        XCTAssertEqual(model.metrics.sizeFactor, 1.22 * 1.2, accuracy: 0.0001)
        XCTAssertEqual(model.substrate, .glass(isDark: true, washOpacity: 0.45))
        XCTAssertEqual(model.symbol, SlotSymbol(glyph: "中"))
        XCTAssertEqual([model.title, model.detail], ["中文", "Pinyin - Simplified"])
        XCTAssertEqual([model.tileFillHex, model.glyphHex, model.titleHex], ["#33A854", "#FFFFFF", "#FFFFFF"])
        XCTAssertEqual(model.detailOpacity, 0.78)
        XCTAssertNil(model.barHex)
        XCTAssertFalse(model.isRightToLeft)
        XCTAssertTrue(model.cells.isEmpty)
    }

    func testUnknownThemeFallsBackAndUnknownSlotHasNoModel() throws {
        let model = try model(config(theme: "deleted-theme"))
        XCTAssertEqual(model.themeID, "builtin.glass")
        XCTAssertEqual(model.fellBackFromThemeID, "deleted-theme")
        XCTAssertNil(IndicatorBubbleResolver.model(
            config: .default, themes: [], sources: sources, slotID: InputRole(rawValue: "missing"),
            previousSlotID: nil, source: nil, context: dark
        ))
    }

    func testColorSettingFeedsSlotThemes() throws {
        XCTAssertEqual(try model(config(theme: nil) { $0.switchIndicatorColorStyle = .accent }).tileFillHex, "#FF2D55")
        XCTAssertEqual(try model(config(theme: nil) { $0.switchIndicatorColorStyle = .monochrome }).tileFillHex, "#8E8E93")

        let paper = try model(config(theme: "builtin.paper-slots") { $0.switchIndicatorColorStyle = .monochrome })
        XCTAssertEqual(paper.substrate, .paper(hex: "#E9E9E5"))
        XCTAssertEqual([paper.tileFillHex, paper.titleHex, paper.detailHex], ["#242321", "#242321", "#242321"])
        XCTAssertEqual(paper.detailOpacity, 0.72, accuracy: 0.0001)
        XCTAssertEqual(paper.highlightStrength, 0)
    }

    func testInkThemesIgnoreSlotTintsAndKnockTheGlyphOut() throws {
        for slot in [InputRole.english, .japanese] {
            let model = try model(config(theme: "builtin.paper-two-inks"), slot: slot)
            XCTAssertEqual([model.tileFillHex, model.glyphHex], ["#C65F38", "#FAFAF7"])
            XCTAssertEqual([model.titleHex, model.detailHex], ["#2148B8", "#2148B8"])
        }
        XCTAssertEqual(try model(config(theme: "builtin.paper-one-ink")).tileFillHex, "#2148B8")
    }

    func testPaleSlotColourIsDeepenedOnPaperButStoredValueIsKept() throws {
        let pale = try config(theme: "builtin.paper-slots").settingSlotTint("#FFF59D", for: .chinese)
        let model = try model(pale)
        let fill = try XCTUnwrap(model.tileFillHex)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(fill, "#E9E9E5")), 3.0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(model.glyphHex, fill)), 3.0)
        XCTAssertEqual(pale.slot(.chinese)?.tintHex, "#FFF59D")
    }

    func testDisplayIsCoercedAndTextOnlyTitlesCarryTheSlotColour() throws {
        let tile = try model(config(theme: "builtin.tile") { $0.switchIndicatorContentStyle = .textOnly })
        XCTAssertEqual(tile.display, .iconOnly)
        XCTAssertEqual(tile.substrate, BubbleSubstrate.none)

        let typographic = try model(config(theme: "builtin.typographic"))
        XCTAssertEqual(typographic.display, .textOnly)
        XCTAssertNil(typographic.tileFillHex)
        XCTAssertEqual([typographic.titleHex, typographic.barHex], ["#63365F", "#63365F"])

        let line = try model(config(theme: "builtin.line") { $0.switchIndicatorContentStyle = .textOnly })
        XCTAssertNil(line.tileFillHex)
        XCTAssertEqual(line.barHex, "#33A854")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(line.titleHex, "#1E1E22")), 4.5)
        XCTAssertNotEqual(line.titleHex, "#FFFFFF")
    }

    func testRightToLeftTargetAndMissingSource() throws {
        let arabic = InputSourceInfo(id: "com.apple.keylayout.Arabic", localizedName: "Arabic", languages: ["ar"], isSelectCapable: true)
        let added = try SwitcherConfig.default.addingSlot(for: arabic).config
        let model = try XCTUnwrap(IndicatorBubbleResolver.model(
            config: added, themes: BuiltInIndicatorThemes.all, sources: sources + [arabic],
            slotID: InputRole(rawValue: "arabic"), previousSlotID: nil, source: arabic, context: dark
        ))
        XCTAssertTrue(model.isRightToLeft)
        XCTAssertEqual([model.symbol.glyph, model.title], ["ع", "العربية"])

        let unresolved = try XCTUnwrap(IndicatorBubbleResolver.model(
            config: .default, themes: BuiltInIndicatorThemes.all, sources: [], slotID: .english,
            previousSlotID: nil, source: nil, context: dark
        ))
        XCTAssertEqual([unresolved.title, unresolved.detail, unresolved.symbol.glyph], ["English", "No input method selected", "E"])
    }

    func testSwitcherCellsCoverEverySlotWithThePreviousIndex() throws {
        let mono = try model(config(theme: "builtin.switcher"), slot: .japanese, previous: .english)
        XCTAssertEqual(mono.cells.map(\.symbol.glyph), ["A", "中", "あ"])
        XCTAssertEqual(mono.cells.map(\.name), ["English", "中文", "日本語"])
        XCTAssertEqual(Set(mono.cells.map(\.fillHex)), ["#FFFFFF"])
        XCTAssertEqual(mono.cells[0].glyphHex, DisplayTint.darkGlyphHex)
        XCTAssertEqual([mono.activeIndex, mono.previousIndex], [2, 0])

        var eight = SwitcherConfig(slots: [], bindings: [], inputSources: [:])
        let languages = ["en", "de", "fr", "ja", "ko", "ru", "ar", "el"]
        let installed = languages.map { InputSourceInfo(id: "source.\($0)", localizedName: "Source \($0)", languages: [$0], isSelectCapable: true) }
        for source in installed { eight = try eight.addingSlot(for: source).config }
        eight.switchIndicatorThemeID = "builtin.switcher-tint"
        let tinted = try XCTUnwrap(IndicatorBubbleResolver.model(
            config: eight, themes: BuiltInIndicatorThemes.all, sources: installed, slotID: eight.slots[7].id,
            previousSlotID: InputRole(rawValue: "gone"), source: installed[7], context: dark
        ))
        XCTAssertEqual(tinted.cells.map(\.symbol.glyph), ["EN", "DE", "FR", "あ", "한", "Я", "ع", "Ω"])
        XCTAssertEqual(tinted.cells.count, 8)
        XCTAssertEqual(tinted.activeIndex, 7)
        XCTAssertNil(tinted.previousIndex)
        // The slot name under the glyph is small text in the glyph colour.
        for cell in tinted.cells {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(cell.fillHex, cell.glyphHex)), 4.5)
        }

        // A two-letter glyph is under the large size: the 3.94:1 tile ink hands over to the text ink.
        eight.switchIndicatorThemeID = "builtin.paper-two-inks"
        let printed = try XCTUnwrap(IndicatorBubbleResolver.model(
            config: eight, themes: BuiltInIndicatorThemes.all, sources: installed, slotID: eight.slots[1].id,
            previousSlotID: nil, source: installed[1], context: dark
        ))
        XCTAssertEqual([printed.symbol.glyph, printed.tileFillHex, printed.glyphHex], ["DE", "#2148B8", "#FAFAF7"])
    }

    func testATileWithAMarkMeetsTheTextMinimum() throws {
        var config = SwitcherConfig(slots: [], bindings: [], inputSources: [:])
        let installed = ["Pinyin", "Wubi"].map {
            InputSourceInfo(id: "source.\($0)", localizedName: $0, languages: ["zh-Hans"], isSelectCapable: true)
        }
        for source in installed { config = try config.addingSlot(for: source).config }
        let model = try XCTUnwrap(IndicatorBubbleResolver.model(
            config: config, themes: BuiltInIndicatorThemes.all, sources: installed, slotID: config.slots[0].id,
            previousSlotID: nil, source: installed[0], context: dark
        ))
        XCTAssertNotNil(model.symbol.mark)
        let fill = try XCTUnwrap(model.tileFillHex)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(InkLegibility.contrast(fill, model.glyphHex)), 4.5)
    }

    func testAccessibilityContextsReplaceTheGlass() throws {
        let reduced = IndicatorRenderContext(isDarkAppearance: false, accentHex: "#FF2D55", reduceTransparency: true)
        let solid = try model(context: reduced)
        XCTAssertEqual(solid.substrate, .solid(hex: "#F2F2F4"))
        XCTAssertEqual([solid.titleHex, solid.detailHex], ["#1D1D1F", "#1D1D1F"])
        XCTAssertEqual(solid.detailOpacity, 0.74)
        XCTAssertEqual(solid.strokeOpacity, 0.16)

        let contrast = IndicatorRenderContext(isDarkAppearance: true, accentHex: "#FF2D55", increaseContrast: true)
        let strong = try model(context: contrast)
        XCTAssertEqual(strong.substrate, .solid(hex: "#1E1E22"))
        XCTAssertEqual([strong.strokeOpacity, strong.highlightStrength, strong.detailOpacity], [0.55, 0, 1])
    }
}
