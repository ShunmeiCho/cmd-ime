import XCTest
@testable import KeyboardSwitcherCore

/// Builds a slot list with one input source per slot, named the way addingSlot names them.
struct IndicatorSlotFixture {
    let slots: [SwitchSlot]
    let sources: [InputRole: InputSourceInfo]

    /// Entries are (language tag, source name, slot name or nil for the automatic English name).
    init(_ entries: [(language: String?, sourceName: String, slotName: String?)]) {
        var slots: [SwitchSlot] = []
        var sources: [InputRole: InputSourceInfo] = [:]
        for (offset, entry) in entries.enumerated() {
            let id = InputRole(rawValue: "slot-\(offset)")
            let source = InputSourceInfo(
                id: "source.\(offset)",
                localizedName: entry.sourceName,
                languages: entry.language.map { [$0] } ?? [],
                isSelectCapable: true
            )
            let automaticName = source.primaryLanguage
                .flatMap { Locale(identifier: "en_US").localizedString(forLanguageCode: $0) } ?? entry.sourceName
            slots.append(SwitchSlot(
                id: id,
                name: entry.slotName ?? automaticName,
                tintHex: SlotPalette.colors[offset % SlotPalette.colors.count]
            ))
            sources[id] = source
        }
        self.slots = slots
        self.sources = sources
    }

    static func languages(_ tags: [String]) -> IndicatorSlotFixture {
        IndicatorSlotFixture(tags.map { (language: $0, sourceName: "Source \($0)", slotName: nil) })
    }

    func symbolTexts() -> [String] {
        let symbols = SlotSymbolResolver.symbols(for: slots, sources: sources)
        return slots.map { slot in
            guard let symbol = symbols[slot.id] else { return "missing" }
            return [symbol.glyph, symbol.mark].compactMap { $0 }.joined(separator: " ")
        }
    }
}

final class SlotSymbolTests: XCTestCase {
    func testCommonLanguageSets() {
        XCTAssertEqual(IndicatorSlotFixture.languages(["en", "zh-Hans", "ja"]).symbolTexts(), ["A", "中", "あ"])
        XCTAssertEqual(IndicatorSlotFixture.languages(["ko", "en"]).symbolTexts(), ["한", "A"])
        XCTAssertEqual(IndicatorSlotFixture.languages(["de", "fr", "en"]).symbolTexts(), ["DE", "FR", "EN"])
        XCTAssertEqual(IndicatorSlotFixture.languages(["ru", "ar", "en"]).symbolTexts(), ["Я", "ع", "A"])
    }

    func testEightSlotsStayPairwiseDistinct() {
        let fixture = IndicatorSlotFixture([
            ("en", "ABC", nil), ("de", "German", nil),
            ("zh-Hans", "Pinyin - Simplified", nil), ("zh-Hans", "Wubi - Simplified", nil),
            ("ja", "Hiragana", nil), ("ko", "2-Set Korean", nil), ("ru", "Russian", nil), ("ar", "Arabic", nil),
        ])
        let texts = fixture.symbolTexts()
        XCTAssertEqual(texts, ["EN", "DE", "中 P", "中 W", "あ", "한", "Я", "ع"])
        XCTAssertEqual(Set(texts).count, texts.count)
    }

    func testChineseScriptsNameThemselvesAndEqualInitialsFallBackToOrdinals() {
        XCTAssertEqual(IndicatorSlotFixture.languages(["zh-Hans", "zh-Hant"]).symbolTexts(), ["简", "繁"])
        let sameInitial = IndicatorSlotFixture([("ja", "Hiragana", nil), ("ja", "Half-width Katakana", nil)])
        XCTAssertEqual(sameInitial.symbolTexts(), ["あ 1", "あ 2"])
    }

    func testOverrideWinsAndStaysOutOfTieGroups() {
        let base = IndicatorSlotFixture([("zh-Hans", "Pinyin - Simplified", nil), ("zh-Hans", "Wubi - Simplified", nil)])
        var slots = base.slots
        slots[0].symbol = " Py "
        let symbols = SlotSymbolResolver.symbols(for: slots, sources: base.sources)
        XCTAssertEqual(symbols[slots[0].id], SlotSymbol(glyph: "Py"))
        XCTAssertEqual(symbols[slots[1].id], SlotSymbol(glyph: "中"))
    }

    func testOverrideValidation() {
        XCTAssertEqual(SlotSymbolResolver.validatedOverride("中"), "中")
        XCTAssertEqual(SlotSymbolResolver.validatedOverride("e\u{301}n"), "e\u{301}n")
        XCTAssertNil(SlotSymbolResolver.validatedOverride("ABC"))
        XCTAssertNil(SlotSymbolResolver.validatedOverride("  "))
        XCTAssertNil(SlotSymbolResolver.validatedOverride("A\u{7}"))
        XCTAssertNil(SlotSymbolResolver.validatedOverride(nil))
    }

    func testFallbacksForUnknownLanguages() {
        XCTAssertEqual(IndicatorSlotFixture([("xx", "Foo", nil)]).symbolTexts(), ["F"])
        XCTAssertEqual(IndicatorSlotFixture([(nil, "", "mine")]).symbolTexts(), ["M"])
        XCTAssertEqual(SlotSymbolResolver.baseGlyph(language: "sr_Cyrl", sourceName: "Serbian"), "Ђ")
        XCTAssertEqual(SlotSymbolResolver.baseGlyph(language: "tg-Cyrl", sourceName: "Tajik"), "Ж")
        XCTAssertEqual(SlotSymbolResolver.baseGlyph(language: nil, sourceName: ""), "?")
    }

    func testSettingSlotSymbolValidatesAndClears() throws {
        let config = SwitcherConfig.default
        let updated = try config.settingSlotSymbol("EN", for: .english)
        XCTAssertEqual(updated.slot(.english)?.symbol, "EN")
        XCTAssertNil(config.slot(.english)?.symbol)
        XCTAssertNil(try updated.settingSlotSymbol("", for: .english).slot(.english)?.symbol)
        XCTAssertThrowsError(try config.settingSlotSymbol("ABC", for: .english)) {
            XCTAssertEqual($0 as? SlotError, .invalidSymbol("ABC"))
        }
        XCTAssertThrowsError(try config.settingSlotSymbol("A", for: InputRole(rawValue: "missing"))) {
            XCTAssertEqual($0 as? SlotError, .unknownSlot(InputRole(rawValue: "missing")))
        }
    }

    func testSymbolCodecKeepsOldFilesLoadingAndDropsInvalidValues() throws {
        let plain = Data(##"{"id":"english","name":"English","tintHex":"#4D8CFF"}"##.utf8)
        XCTAssertNil(try JSONDecoder().decode(SwitchSlot.self, from: plain).symbol)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(SwitchSlot.legacyDefaults[0]), as: UTF8.self).contains("symbol"))

        let invalid = Data(##"{"id":"english","name":"English","tintHex":"#4D8CFF","symbol":"ABCD"}"##.utf8)
        XCTAssertNil(try JSONDecoder().decode(SwitchSlot.self, from: invalid).symbol)

        let slot = SwitchSlot(id: .english, name: "English", tintHex: "#4D8CFF", symbol: "En")
        XCTAssertEqual(try JSONDecoder().decode(SwitchSlot.self, from: JSONEncoder().encode(slot)), slot)
    }
}
