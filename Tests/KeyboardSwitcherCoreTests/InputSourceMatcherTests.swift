import XCTest
@testable import KeyboardSwitcherCore

final class InputSourceMatcherTests: XCTestCase {
    private func source(_ id: String, selectable: Bool = true) -> InputSourceInfo {
        InputSourceInfo(id: id, localizedName: id, languages: ["en"], isSelectCapable: selectable)
    }

    func testScanJSONPreservesSourceFieldsAndOrder() throws {
        let json = #"[{"id":"z","localizedName":"First","languages":["ko"],"isSelectCapable":true},{"id":"a","localizedName":"Second","languages":["en","de"],"isSelectCapable":false}]"#
        let decoded = try InputSourceMatcher.decodeScanJSON(Data(json.utf8))
        XCTAssertEqual(decoded, [
            InputSourceInfo(id: "z", localizedName: "First", languages: ["ko"], isSelectCapable: true),
            InputSourceInfo(id: "a", localizedName: "Second", languages: ["en", "de"], isSelectCapable: false),
        ])
    }

    func testScanJSONAcceptsEmptyList() throws {
        XCTAssertEqual(try InputSourceMatcher.decodeScanJSON(Data("[]\n".utf8)), [])
    }

    func testScanJSONRejectsMalformedAndIncompleteOutput() {
        for json in ["", "scanner failed", "{}", #"[{"id":"missing-fields"}]"#, "notice\n[]"] {
            XCTAssertThrowsError(try InputSourceMatcher.decodeScanJSON(Data(json.utf8)), json)
        }
    }

    func testSourceAvailabilityRequiresBothEnabledAndSelectCapable() {
        XCTAssertTrue(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: true, isSelectCapable: true))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: false, isSelectCapable: true))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: true, isSelectCapable: false))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: false, isSelectCapable: false))
    }

    func testSourceAvailabilityRejectsMissingProperties() {
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: nil, isSelectCapable: true))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: true, isSelectCapable: nil))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: nil, isSelectCapable: false))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: false, isSelectCapable: nil))
        XCTAssertFalse(InputSourceMatcher.isEnabledAndSelectCapable(isEnabled: nil, isSelectCapable: nil))
    }

    func testDisabledSourceIsRemovedEvenWhenEnumerationStillContainsItsID() {
        let korean = InputSourceInfo(
            id: "com.apple.inputmethod.Korean.2SetKorean", localizedName: "2-Set Korean",
            languages: ["ko"], isSelectCapable: true
        )
        let english = source("com.apple.keylayout.ABC")
        var config = SwitcherConfig.default
        config.inputSources["english"] = RoleInputSourcePreference(preferredIDs: [korean.id, english.id])
        let enumerated = [korean, english]
        let scan = { (koreanEnabled: Bool) in
            enumerated.filter {
                InputSourceMatcher.isEnabledAndSelectCapable(
                    isEnabled: $0.id == korean.id ? koreanEnabled : true,
                    isSelectCapable: $0.isSelectCapable
                )
            }
        }

        let before = scan(true)
        let after = scan(false)
        XCTAssertEqual(before.map(\.id), [korean.id, english.id])
        XCTAssertEqual(after.map(\.id), [english.id])
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .english, sources: after, config: config)?.id, english.id)
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: before, current: after), [])
        let reenabled = scan(true)
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: after, current: reenabled), [korean])
    }

    func testSelectedSourceSlotMatchesPreferredSource() {
        let preferred = source("preferred")
        var config = SwitcherConfig.default
        config.pinInputSourceID(preferred.id, for: .chinese)
        XCTAssertEqual(InputSourceMatcher.slotID(forSelectedSourceID: preferred.id, sources: [preferred], config: config), .english)
        // Explicitly select a source that no earlier slot resolves to.
        config.inputSources["english"] = RoleInputSourcePreference()
        XCTAssertEqual(InputSourceMatcher.slotID(forSelectedSourceID: preferred.id, sources: [preferred], config: config), .chinese)
    }

    func testSelectedSourceSlotMatchesFallbackThroughExistingMatcherTiers() {
        let fallback = source("chosen.english")
        let preferences = [
            RoleInputSourcePreference(preferredIDs: ["missing"], fallbackLanguage: "en"),
            RoleInputSourcePreference(preferredIDs: ["missing", fallback.id]),
            RoleInputSourcePreference(languagePrefixes: ["en"]),
            RoleInputSourcePreference(nameContains: ["chosen"]),
        ]
        for preference in preferences {
            var config = SwitcherConfig.default
            config.inputSources["english"] = preference
            XCTAssertEqual(InputSourceMatcher.slotID(forSelectedSourceID: fallback.id, sources: [fallback], config: config), .english)
        }
    }

    func testSelectedSourceSlotReturnsNilForUnmatchedOrUnavailableSelection() {
        let preferred = source("preferred")
        let other = source("other")
        var config = SwitcherConfig.default
        config.inputSources["english"] = RoleInputSourcePreference(preferredIDs: [preferred.id])
        let sources = [preferred, other]
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: other.id, sources: sources, config: config))
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: "missing", sources: sources, config: config))
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: nil, sources: sources, config: config))
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: preferred.id, sources: [], config: config))
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: preferred.id, sources: [source(preferred.id, selectable: false)], config: config))
    }

    func testSelectedSourceSlotChoosesFirstResolvedSlotInConfigOrder() {
        let shared = source("shared")
        var config = SwitcherConfig.default
        config.inputSources["english"] = RoleInputSourcePreference(fallbackLanguage: "en")
        config.inputSources["chinese"] = RoleInputSourcePreference(preferredIDs: [shared.id])
        XCTAssertEqual(config.duplicateSlotIDs(for: .english, sources: [shared]), [.chinese])
        XCTAssertEqual(InputSourceMatcher.slotID(forSelectedSourceID: shared.id, sources: [shared], config: config), .english)
        config.slots.swapAt(0, 1)
        XCTAssertEqual(InputSourceMatcher.slotID(forSelectedSourceID: shared.id, sources: [shared], config: config), .chinese)
    }

    func testSelectedSourceSlotReturnsNilForEmptyConfig() {
        let selected = source("selected")
        let empty = SwitcherConfig(slots: [], bindings: [], inputSources: [:])
        XCTAssertNil(InputSourceMatcher.slotID(forSelectedSourceID: selected.id, sources: [selected], config: empty))
    }

    func testNewSelectableSourcesIgnoresExistingIDsAndMetadataChanges() {
        let existing = source("existing")
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [existing], current: [existing]), [])
        var renamed = existing
        renamed.localizedName = "New display name"
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [existing], current: [renamed]), [])
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [], current: []), [])
    }

    func testNewSelectableSourcesReturnsAddedSource() {
        let existing = source("existing")
        let added = source("added")
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [existing], current: [existing, added]), [added])
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [], current: [added]), [added])
    }

    func testNewSelectableSourcesExcludesNonselectableAndAuxiliaryAdditions() {
        let existing = source("existing")
        let unavailable = source("unavailable", selectable: false)
        let palette = source("com.apple.CharacterPaletteIM")
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [existing], current: [existing, unavailable, palette]), [])
    }

    func testNewSelectableSourcesDoesNotReportRemovedSources() {
        let kept = source("kept")
        let removed = source("removed")
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [kept, removed], current: [kept]), [])
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(previous: [kept], current: []), [])
    }

    func testNewSelectableSourcesPreservesCurrentOrder() {
        let existing = source("existing")
        let first = source("z-first")
        let second = source("a-second")
        XCTAssertEqual(InputSourceMatcher.newSelectableSources(
            previous: [existing], current: [first, existing, source("hidden", selectable: false), second]
        ), [first, second])
    }

    func testDynamicFallbackUsesPrimaryLanguageAndPreferredIDWins() {
        let role = InputRole(rawValue: "german")
        var config = SwitcherConfig.default
        config.slots.append(SwitchSlot(id: role, name: "German", tintHex: "#123456"))
        config.inputSources[role.rawValue] = RoleInputSourcePreference(preferredIDs: ["preferred"], fallbackLanguage: "de")
        let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en", "de", "es", "fr"], isSelectCapable: true)
        let german = InputSourceInfo(id: "german", localizedName: "German", languages: ["de-DE"], isSelectCapable: true)
        XCTAssertEqual(InputSourceMatcher.match(for: role, sources: [abc], config: config).tier, .none)
        let fallback = InputSourceMatcher.match(for: role, sources: [abc, german], config: config)
        XCTAssertEqual(fallback.source, german)
        XCTAssertEqual(fallback.tier, .fallbackLanguage)
        XCTAssertEqual(fallback.matchedValue, "de")
        let preferred = InputSourceInfo(id: "preferred", localizedName: "Preferred", languages: ["de"], isSelectCapable: true)
        XCTAssertEqual(InputSourceMatcher.match(for: role, sources: [german, preferred], config: config).tier, .preferredID)
        XCTAssertEqual(InputSourceMatcher.match(for: InputRole(rawValue: "unknown"), sources: [abc, german], config: config).tier, .none)
    }

    func testGermanSlotDoesNotFallbackToMultilingualABC() throws {
        // Captured from keyboardctl scan --json on macOS: ABC advertises German
        // among many secondary languages, but its primary language is English.
        let abc = InputSourceInfo(
            id: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            languages: [
                "en", "acf", "af", "asa", "bem", "bez", "ca", "ceb", "cgg", "co", "da", "dav",
                "de", "es", "eu", "fil", "fr", "fur", "ga", "gcf", "gd", "gl", "gsw", "guz", "gv",
                "hi_Latn", "ht", "ia", "id", "ie", "io", "isc", "it", "jbo", "jmc", "jv", "kaj",
                "kde", "kea", "kl", "kln", "ksb", "kw", "lb", "lij", "lmo", "luo", "luy", "mfe",
                "mgh", "ms", "nb", "nd", "nds", "nl", "nn", "no", "nr", "nyn", "oc", "om", "pms",
                "pqm", "pt", "rej", "rm", "rn", "rof", "rw", "rwk", "saq", "sbp", "sc", "seh",
                "sg", "shp", "sn", "so", "sq", "ss", "st", "su", "su_Latn", "sv", "sw", "teo",
                "tn", "tok", "trv", "ts", "vec", "vmw", "vun", "wa", "xh", "xog", "za", "zu",
            ],
            isSelectCapable: true
        )
        let missingGerman = InputSourceInfo(id: "missing.german", localizedName: "German", languages: ["de"], isSelectCapable: true)
        let added = try SwitcherConfig.default.addingSlot(for: missingGerman)
        XCTAssertNil(InputSourceMatcher.bestMatch(for: added.slot.id, sources: [abc], config: added.config))
    }

    func testPreferredIDBeatsLanguageFallback() {
        var config = SwitcherConfig.default
        config.pinInputSourceID("custom.zh", for: .chinese)

        let sources = [
            InputSourceInfo(
                id: "first.zh",
                localizedName: "Chinese",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "custom.zh",
                localizedName: "My Pinyin",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .chinese, sources: sources, config: config)

        XCTAssertEqual(match?.id, "custom.zh")
    }

    func testLanguageFallbackFindsJapanese() {
        let sources = [
            InputSourceInfo(
                id: "emoji",
                localizedName: "Emoji",
                languages: ["en"],
                isSelectCapable: false
            ),
            InputSourceInfo(
                id: "jp",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .japanese, sources: sources, config: .default)

        XCTAssertEqual(match?.id, "jp")
    }

    func testJapanesePaletteDoesNotBeatRealInputMethod() {
        var config = SwitcherConfig.default
        config.pinInputSourceID("com.apple.50onPaletteIM", for: .japanese)

        let sources = [
            InputSourceInfo(
                id: "com.apple.50onPaletteIM",
                localizedName: "Japanese Kana Palette",
                languages: ["ja"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        let match = InputSourceMatcher.bestMatch(for: .japanese, sources: sources, config: config)

        XCTAssertEqual(match?.id, "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese")
    }

    func testSelectableSourcesExcludeAuxiliaryInputSources() {
        let sources = [
            InputSourceInfo(
                id: "com.apple.keylayout.ABC",
                localizedName: "ABC",
                languages: ["en"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.50onPaletteIM",
                localizedName: "Japanese Kana Palette",
                languages: ["ja"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "com.apple.CharacterPaletteIM",
                localizedName: "Emoji & Symbols",
                languages: ["en"],
                isSelectCapable: true
            ),
        ]

        let selectable = InputSourceMatcher.selectableSources(from: sources)

        XCTAssertEqual(selectable.map(\.id), ["com.apple.keylayout.ABC"])
    }

    func testMatchReportsPreferredIDTier() {
        var config = SwitcherConfig.default
        config.pinInputSourceID("custom.zh", for: .chinese)

        let sources = [
            InputSourceInfo(
                id: "first.zh",
                localizedName: "Chinese",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
            InputSourceInfo(
                id: "custom.zh",
                localizedName: "My Pinyin",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
        ]

        let result = InputSourceMatcher.match(for: .chinese, sources: sources, config: config)

        XCTAssertEqual(result.source?.id, "custom.zh")
        XCTAssertEqual(result.tier, .preferredID)
        XCTAssertEqual(result.matchedValue, "custom.zh")
    }

    func testMatchReportsLanguagePrefixTier() {
        let sources = [
            InputSourceInfo(
                id: "emoji",
                localizedName: "Emoji",
                languages: ["en"],
                isSelectCapable: false
            ),
            InputSourceInfo(
                id: "jp",
                localizedName: "Hiragana",
                languages: ["ja"],
                isSelectCapable: true
            ),
        ]

        let result = InputSourceMatcher.match(for: .japanese, sources: sources, config: .default)

        XCTAssertEqual(result.source?.id, "jp")
        XCTAssertEqual(result.tier, .languagePrefix)
        XCTAssertEqual(result.matchedValue, "ja")
    }

    func testMatchReportsNameContainsTier() {
        var config = SwitcherConfig.default
        config.inputSources[InputRole.chinese.rawValue] = RoleInputSourcePreference(
            preferredIDs: [],
            languagePrefixes: [],
            nameContains: ["Pinyin"]
        )

        let sources = [
            InputSourceInfo(
                id: "custom.pinyin",
                localizedName: "My Pinyin Method",
                languages: [],
                isSelectCapable: true
            ),
        ]

        let result = InputSourceMatcher.match(for: .chinese, sources: sources, config: config)

        XCTAssertEqual(result.source?.id, "custom.pinyin")
        XCTAssertEqual(result.tier, .nameContains)
        XCTAssertEqual(result.matchedValue, "pinyin")
    }

    func testMatchReportsNoneTierWhenNothingMatches() {
        var config = SwitcherConfig.default
        config.inputSources[InputRole.japanese.rawValue] = RoleInputSourcePreference(
            preferredIDs: [],
            languagePrefixes: [],
            nameContains: []
        )

        let sources = [
            InputSourceInfo(
                id: "custom.zh",
                localizedName: "My Pinyin",
                languages: ["zh-Hans"],
                isSelectCapable: true
            ),
        ]

        let result = InputSourceMatcher.match(for: .japanese, sources: sources, config: config)

        XCTAssertNil(result.source)
        XCTAssertEqual(result.tier, .none)
        XCTAssertNil(result.matchedValue)
    }

    func testDisplayLanguagesTruncatesLongLanguageLists() {
        let source = InputSourceInfo(
            id: "abc",
            localizedName: "ABC",
            languages: ["en", "af", "asa", "bem", "bez", "ca"],
            isSelectCapable: true
        )

        XCTAssertEqual(source.displayLanguages, "en, af, asa, bem +2 more")
    }
}
