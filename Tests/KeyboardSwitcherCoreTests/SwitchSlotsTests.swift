import XCTest
@testable import KeyboardSwitcherCore

final class SwitchSlotsTests: XCTestCase {
    private func source(_ id: String = "ko.one", _ language: String = "ko") -> InputSourceInfo {
        InputSourceInfo(id: id, localizedName: "Source \(id)", languages: [language], isSelectCapable: true)
    }

    func testAddingGeneratesIdentityPreferenceColorAndTrigger() throws {
        let result = try SwitcherConfig.default.addingSlot(for: source())
        XCTAssertEqual(result.slot.id.rawValue, "korean")
        XCTAssertEqual(result.slot.name, "Korean")
        XCTAssertEqual(result.slot.tintHex, SlotPalette.colors[3])
        XCTAssertEqual(result.config.preference(for: result.slot.id), RoleInputSourcePreference(preferredIDs: ["ko.one"], fallbackLanguage: "ko"))
        XCTAssertEqual(result.config.bindings.last?.trigger.keyName, "left-option")
        let second = try result.config.addingSlot(for: source("ko.two"))
        XCTAssertEqual(second.slot.id.rawValue, "korean-2")
        XCTAssertEqual(second.slot.name, "Source ko.two")
        XCTAssertThrowsError(try second.config.addingSlot(for: source())) { error in
            XCTAssertEqual(error as? SlotError, .sourceAlreadyUsed)
        }
    }

    func testInsertionMovementAndRenamingArePure() throws {
        let original = SwitcherConfig.default
        let result = try original.addingSlot(for: source(), at: -10)
        XCTAssertEqual(result.config.slots.first?.id, result.slot.id)
        let moved = result.config.movingSlot(from: 0, to: 100)
        XCTAssertEqual(moved.slots.last?.id, result.slot.id)
        XCTAssertEqual(moved.movingSlot(from: -1, to: 0), moved)
        let renamed = try moved.renamingSlot(result.slot.id, to: "  Work  \n")
        XCTAssertEqual(renamed.slots.last?.name, "Work")
        XCTAssertEqual(renamed.slots.last?.id, result.slot.id)
        XCTAssertThrowsError(try moved.renamingSlot(result.slot.id, to: " \n"))
        XCTAssertThrowsError(try moved.renamingSlot(InputRole(rawValue: "missing"), to: "X"))
        XCTAssertEqual(original.slots, SwitchSlot.legacyDefaults)
    }

    func testNormalizationDeduplicatesAndRestoresDisabledOrphans() throws {
        let orphan = InputRole(rawValue: "orphan")
        var config = SwitcherConfig.default
        config.version = 1
        let first = config.slots[0]
        var duplicate = first
        duplicate.name = "Discard this duplicate"
        duplicate.tintHex = "#000000"
        config.slots = [first, duplicate]
        config.bindings = [KeyBinding(trigger: try ShortcutParser.parse("left-option"), action: .switchInputSource(orphan), enabled: false)]
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.slots.map(\.id), [.english, orphan])
        XCTAssertEqual(decoded.slots.first, first)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.migrated().version, 2)
        XCTAssertEqual(SwitcherConfig.normalizedSlots([], bindings: []), SwitchSlot.legacyDefaults)
    }

    func testRemovalCleansOnlySlotOwnedDataAndRejectsLastAndUnknown() throws {
        var config = SwitcherConfig.default
        let remap = KeyBinding(trigger: try ShortcutParser.parse("left-option"), action: .sendKey(try ShortcutParser.parse("a")))
        config.bindings.append(remap)
        config.switchIndicatorCustomRoleColorHexes["chinese"] = "#123456"
        let removed = try config.removingSlot(.chinese)
        XCTAssertNil(removed.slot(.chinese))
        XCTAssertNil(removed.inputSources["chinese"])
        XCTAssertNil(removed.switchIndicatorCustomRoleColorHexes["chinese"])
        XCTAssertTrue(removed.bindings.contains(remap))
        XCTAssertThrowsError(try removed.removingSlot(.chinese))
        let last = try removed.removingSlot(.japanese)
        XCTAssertThrowsError(try last.removingSlot(.english))
    }

    func testPreferredAssignmentUniquenessUsesOnlyOtherFirstIDs() throws {
        var config = SwitcherConfig.default
        config.inputSources["chinese"]?.preferredIDs.append("allowed")
        XCTAssertNoThrow(try config.addingSlot(for: source("allowed")))
        XCTAssertThrowsError(try config.assigningInputSource(source("com.apple.keylayout.ABC"), to: .chinese)) { error in
            XCTAssertEqual(error as? SlotError, .sourceAlreadyUsed)
        }
        let assigned = try config.assigningInputSource(source("allowed"), to: .chinese)
        XCTAssertEqual(assigned.preference(for: .chinese).preferredIDs.first, "allowed")
        XCTAssertEqual(assigned.preference(for: .chinese).languagePrefixes, ["zh"])
        XCTAssertNil(assigned.preference(for: .chinese).fallbackLanguage)
        let added = try config.addingSlot(for: source())
        let changed = try added.config.assigningInputSource(source("de.one", "de"), to: added.slot.id)
        XCTAssertEqual(changed.preference(for: added.slot.id).fallbackLanguage, "de")
    }

    func testDuplicateResolutionIsAllowedAndReportedInSlotOrder() {
        var config = SwitcherConfig.default
        let abc = source("com.apple.keylayout.ABC", "en")
        config.inputSources["chinese"]?.preferredIDs.append(abc.id)
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .english, sources: [abc], config: config), abc)
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .chinese, sources: [abc], config: config), abc)
        XCTAssertEqual(config.duplicateSlotIDs(for: .english, sources: [abc]), [.chinese])
        XCTAssertEqual(config.duplicateSlotIDs(for: .chinese, sources: [abc]), [.english])
        XCTAssertEqual(config.duplicateSlotIDs(for: .japanese, sources: [abc]), [])
        XCTAssertEqual(SwitcherConfig.default.duplicateSlotIDs(for: .english, sources: [abc]), [])
    }

    func testTriggerSuggestionsSkipRemapsDoubleTapsAndStopAfterFive() throws {
        var config = SwitcherConfig(bindings: [], inputSources: [:])
        let names = ["left-command", "right-command", "left-option", "right-option", "left-control"]
        for name in names {
            XCTAssertEqual(config.nextFreeOneShotTrigger()?.keyName, name)
            config.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("double-\(name)"), action: .sendKey(try ShortcutParser.parse("a"))))
        }
        XCTAssertNil(config.nextFreeOneShotTrigger())
        XCTAssertNotNil(config.conflictingBinding(for: try ShortcutParser.parse("left-command"), excluding: .english))
        config.bindings = [KeyBinding(trigger: try ShortcutParser.parse("command+k"), action: .switchInputSource(.chinese))]
        XCTAssertNotNil(config.conflictingBinding(for: try ShortcutParser.parse("command+k"), excluding: .english))
        XCTAssertNil(config.conflictingBinding(for: try ShortcutParser.parse("command+k"), excluding: .chinese))
    }

    func testLookupExactIDPrecedesAmbiguousNamesAndCaseInsensitiveRequiresUnique() {
        var config = SwitcherConfig.default
        config.slots[1].name = "english"
        XCTAssertEqual(config.slot(matching: "english")?.id, .english)
        XCTAssertNil(config.slot(matching: "ENGLISH"))
        XCTAssertEqual(config.displayName(for: .chinese), "english")
        XCTAssertEqual(config.displayName(for: InputRole(rawValue: "missing")), "missing")
    }

    func testClampedInsertionAndFinalDestinationMovementPreserveMetadata() throws {
        let config = SwitcherConfig.default
        let added = try config.addingSlot(for: source(), name: "  Work  ", at: 999)
        XCTAssertEqual(added.config.slots.last, added.slot)
        XCTAssertEqual(added.slot.name, "Work")
        let moved = added.config.movingSlot(from: 3, to: 1)
        XCTAssertEqual(moved.slots.map(\.id), [.english, added.slot.id, .chinese, .japanese])
        XCTAssertEqual(moved.slots[1], added.slot)
        XCTAssertEqual(moved.bindings, added.config.bindings)
        XCTAssertEqual(moved.movingSlot(from: 1, to: -999).slots.first, added.slot)
    }

    func testPalettePrefersAvailableLegacyColorAndDoesNotRecolorSurvivors() throws {
        let config = try SwitcherConfig.default.removingSlot(.chinese)
        let added = try config.addingSlot(for: source("zh.new", "zh"))
        XCTAssertEqual(added.slot.id, .chinese)
        XCTAssertEqual(added.slot.tintHex, "#33A854")
        XCTAssertEqual(added.config.slot(.japanese)?.tintHex, "#E3574A")
        XCTAssertEqual(SlotPalette.colors.count, 8)
    }

    func testDisabledBindingsDoNotReserveTriggersAndInvalidAssignmentFails() throws {
        var config = SwitcherConfig.default
        config.bindings[0].enabled = false
        XCTAssertEqual(config.nextFreeOneShotTrigger()?.keyName, "left-command")
        XCTAssertNil(config.conflictingBinding(for: try ShortcutParser.parse("left-command"), excluding: .chinese))
        XCTAssertThrowsError(try config.assigningInputSource(source(), to: InputRole(rawValue: "missing"))) { error in
            XCTAssertEqual(error as? SlotError, .unknownSlot(InputRole(rawValue: "missing")))
        }
        var invalid = source()
        invalid.isSelectCapable = false
        XCTAssertThrowsError(try config.assigningInputSource(invalid, to: .english)) { error in
            XCTAssertEqual(error as? SlotError, .invalidSource)
        }
        XCTAssertThrowsError(try config.addingSlot(for: source(), name: "  "))
    }

    func testLookupLanguageBadgesSlugAndUnassignedSources() throws {
        let config = SwitcherConfig.default
        XCTAssertEqual(config.slot(matching: "ENGLISH")?.id, .english)
        XCTAssertNil(config.slot(matching: "missing"))
        for (language, primary, badge) in [("zh-Hans", "zh", "中"), ("hi_Latn", "hi", "HI"), ("ko", "ko", "한"), ("en", "en", "A"), ("ja", "ja", "あ")] {
            XCTAssertEqual(source("x", language).primaryLanguage, primary)
            XCTAssertEqual(source("x", language).badgeSymbol, badge)
        }
        var unknown = source("x", "")
        unknown.localizedName = "输入"
        XCTAssertNil(unknown.primaryLanguage)
        XCTAssertEqual(try config.addingSlot(for: unknown).slot.id.rawValue, "slot")
        let abc = source("com.apple.keylayout.ABC", "en")
        let emoji = InputSourceInfo(id: "emoji", localizedName: "Emoji", languages: [], isSelectCapable: true)
        XCTAssertEqual(config.unassignedSources(from: [abc, source(), emoji]), [source()])
        XCTAssertThrowsError(try config.addingSlot(for: emoji))
    }
}
