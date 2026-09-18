import XCTest
@testable import KeyboardSwitcherCore

final class SwitchSlotsTests: XCTestCase {
    private func source(_ id: String = "ko.one", _ language: String = "ko") -> InputSourceInfo {
        InputSourceInfo(id: id, localizedName: "Source \(id)", languages: [language], isSelectCapable: true)
    }

    func testSettingSlotTintNormalizesAcceptedHexForms() throws {
        for input in ["#A1B2CF", "#a1b2cf", "#a1B2cF", "A1B2CF", "a1b2cf", " \t#a1B2cF\n", "\n a1b2cf \t"] {
            let updated = try SwitcherConfig.default.settingSlotTint(input, for: .chinese)
            XCTAssertEqual(updated.slot(.chinese)?.tintHex, "#A1B2CF", "input=\(input.debugDescription)")
        }
        for input in ["000000", "ffffff"] {
            XCTAssertEqual(try SwitcherConfig.default.settingSlotTint(input, for: .english).slot(.english)?.tintHex,
                           "#" + input.uppercased())
        }
    }

    func testSettingSlotTintRejectsInvalidFormsAndPreservesOriginalInput() {
        let original = SwitcherConfig.default
        let invalid = ["#ABC", "abc", "#11223344", "11223344", "#GG0000", "12x456", "", " \t\n",
                       "#12345", "#1234567", "##123456", "0x123456", "#12 456", "#１２３４５６", "#aßcde"]
        for input in invalid {
            XCTAssertThrowsError(try original.settingSlotTint(input, for: .english)) { error in
                XCTAssertEqual(error as? SlotError, .invalidTintHex(input))
            }
        }
        XCTAssertEqual(original, .default)
        XCTAssertEqual(SlotError.invalidTintHex("#GG0000").errorDescription,
                       "Invalid slot color \"#GG0000\". Use six hexadecimal digits, such as #4D8CFF.")
    }

    func testSettingSlotTintRejectsUnknownSlotBeforeValidatingColor() {
        let unknown = InputRole(rawValue: "missing")
        for input in ["#123456", ""] {
            XCTAssertThrowsError(try SwitcherConfig.default.settingSlotTint(input, for: unknown)) { error in
                XCTAssertEqual(error as? SlotError, .unknownSlot(unknown))
            }
        }
    }

    func testSettingSlotTintChangesOnlyTargetTintAndLeavesOriginalUntouched() throws {
        let added = try SwitcherConfig.default.addingSlot(for: source())
        var original = added.config.movingSlot(added.slot.id, by: -2)
        original.switchIndicatorCustomRoleColorHexes[added.slot.id.rawValue] = "#ABCDEF"
        original.switchIndicatorCustomColorHex = "#654321"
        original.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("command+k"), action: .sendKey(try ShortcutParser.parse("a"))))
        let snapshot = original
        var expected = snapshot
        let index = try XCTUnwrap(expected.slots.firstIndex { $0.id == added.slot.id })
        expected.slots[index].tintHex = "#12AB34"

        let updated = try original.settingSlotTint(" 12ab34 ", for: added.slot.id)
        XCTAssertEqual(updated, expected)
        XCTAssertEqual(original, snapshot)
    }

    func testSettingSameSlotTintReturnsEqualConfig() throws {
        let original = SwitcherConfig.default
        XCTAssertEqual(try original.settingSlotTint("#4D8CFF", for: .english), original)
        XCTAssertEqual(try original.settingSlotTint(" 4d8cff\n", for: .english), original)
    }

    func testSlotTintSurvivesConfigEncodingRoundTrip() throws {
        let updated = try SwitcherConfig.default.settingSlotTint(" #1a2b3c ", for: .japanese)
        let data = try JSONEncoder().encode(updated)
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: data)
        XCTAssertEqual(decoded.slot(.japanese)?.tintHex, "#1A2B3C")
        XCTAssertEqual(decoded, updated)
    }

    func testMovingEverySourceToEveryFinalIndexMatchesRemoveThenInsert() {
        for count in 1...6 {
            var config = SwitcherConfig.default
            config.slots = (0..<count).map {
                SwitchSlot(id: InputRole(rawValue: "slot-\($0)"), name: "Slot \($0)", tintHex: "#123456")
            }
            let snapshot = config
            for source in 0..<count {
                for destination in 0..<count {
                    var expected = snapshot
                    let movedSlot = expected.slots.remove(at: source)
                    expected.slots.insert(movedSlot, at: destination)
                    XCTAssertEqual(config.movingSlot(from: source, to: destination), expected,
                                   "count=\(count), source=\(source), destination=\(destination)")
                }
            }
            XCTAssertEqual(config, snapshot)
        }
    }

    func testMovingSlotByOffsetClampsAndPreservesMetadata() {
        let config = SwitcherConfig.default
        for (offset, destination) in [(Int.min, 0), (-10, 0), (-1, 0), (0, 1), (1, 2), (10, 2), (Int.max, 2)] {
            XCTAssertEqual(config.movingSlot(.chinese, by: offset), config.movingSlot(from: 1, to: destination))
        }
        XCTAssertEqual(config.movingSlot(.english, by: -1), config)
        XCTAssertEqual(config.movingSlot(.japanese, by: 1), config)
        XCTAssertEqual(config.movingSlot(InputRole(rawValue: "missing"), by: Int.max), config)
        var single = config
        single.slots = [config.slots[0]]
        XCTAssertEqual(single.movingSlot(.english, by: Int.max), single)
        XCTAssertEqual(single.movingSlot(.english, by: Int.min), single)
        var empty = config
        empty.slots = []
        XCTAssertEqual(empty.movingSlot(.english, by: 1), empty)
    }

    func testRenamingRejectsCaseInsensitiveDuplicateNamesAfterTrimming() {
        var config = SwitcherConfig.default
        config.slots[1].name = "  Work Desk \n"
        let snapshot = config
        for name in ["Work Desk", "work desk", "WORK DESK", "\n  wOrK dEsK  "] {
            XCTAssertThrowsError(try config.renamingSlot(.english, to: name)) { error in
                XCTAssertEqual(error as? SlotError, .duplicateName)
            }
        }
        XCTAssertEqual(config, snapshot)
        XCTAssertEqual(SlotError.duplicateName.errorDescription, "Another slot already uses this name. Choose a different name.")
    }

    func testRenamingAllowsOwnNameAndCaseChangeWithoutChangingOtherData() throws {
        let config = SwitcherConfig.default
        XCTAssertEqual(try config.renamingSlot(.english, to: " \nEnglish "), config)
        var expected = config
        expected.slots[0].name = "ENGLISH"
        XCTAssertEqual(try config.renamingSlot(.english, to: " ENGLISH\n"), expected)
        XCTAssertThrowsError(try config.renamingSlot(.english, to: " \n")) { error in
            XCTAssertEqual(error as? SlotError, .invalidName)
        }
        let unknown = InputRole(rawValue: "missing")
        XCTAssertThrowsError(try config.renamingSlot(unknown, to: "English")) { error in
            XCTAssertEqual(error as? SlotError, .unknownSlot(unknown))
        }
    }

    func testRemovalReceiptRoundTripsSlotOrderBindingOffsetsPreferencesAndColors() throws {
        var config = SwitcherConfig.default
        config.slots[1].name = "Work"
        config.slots[1].tintHex = "#123456"
        config.showSwitchIndicator = false
        config.switchIndicatorCustomColorHex = "#ABCDEF"
        config.switchIndicatorCustomRoleColorHexes = ["chinese": "#654321", "english": "#FEDCBA"]
        config.bindings.insert(KeyBinding(trigger: try ShortcutParser.parse("command+k"), action: .sendKey(try ShortcutParser.parse("a"))), at: 2)
        config.bindings.insert(KeyBinding(trigger: try ShortcutParser.parse("option+l"), action: .switchInputSource(.chinese), enabled: false), at: 4)
        config.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("control+j"), action: .switchInputSource(.chinese)))
        config.inputSources["chinese"] = RoleInputSourcePreference(preferredIDs: ["missing.first", "history"], languagePrefixes: ["zh"], nameContains: ["Chinese"], fallbackLanguage: "zh")
        let snapshot = config

        let removal = try config.removingSlotWithReceipt(.chinese)
        XCTAssertEqual(removal.config, try config.removingSlot(.chinese))
        XCTAssertEqual(removal.removed.slot, config.slots[1])
        XCTAssertEqual(removal.removed.index, 1)
        XCTAssertEqual(removal.removed.bindings.map(\.offset), [1, 4, 5])
        XCTAssertEqual(removal.removed.bindings.map(\.binding), [config.bindings[1], config.bindings[4], config.bindings[5]])
        XCTAssertEqual(removal.removed.preference, config.inputSources["chinese"])
        XCTAssertEqual(removal.removed.customIndicatorColorHex, "#654321")
        let restored = try removal.config.restoringSlot(removal.removed)
        XCTAssertEqual(restored.config, snapshot)
        XCTAssertEqual(restored.skippedBindings, [])
        XCTAssertEqual(config, snapshot)
    }

    func testRemovalReceiptPreservesAbsentPreferenceColorAndBindings() throws {
        var config = SwitcherConfig.default
        config.inputSources["japanese"] = nil
        config.bindings.removeAll { $0.action.role == .japanese }
        config.switchIndicatorCustomColorHex = "#123456"
        let removal = try config.removingSlotWithReceipt(.japanese)
        XCTAssertNil(removal.removed.preference)
        XCTAssertNil(removal.removed.customIndicatorColorHex)
        XCTAssertEqual(removal.removed.bindings, [])
        let restored = try removal.config.restoringSlot(removal.removed)
        XCTAssertEqual(restored.config, config)
        XCTAssertNil(restored.config.inputSources["japanese"])
        XCTAssertNil(restored.config.switchIndicatorCustomRoleColorHexes["japanese"])
    }

    func testRemovalReceiptRejectsUnknownAndLastSlot() throws {
        let unknown = InputRole(rawValue: "missing")
        XCTAssertThrowsError(try SwitcherConfig.default.removingSlotWithReceipt(unknown)) { error in
            XCTAssertEqual(error as? SlotError, .unknownSlot(unknown))
        }
        let onlyEnglish = try SwitcherConfig.default.removingSlot(.japanese).removingSlot(.chinese)
        XCTAssertThrowsError(try onlyEnglish.removingSlotWithReceipt(.english)) { error in
            XCTAssertEqual(error as? SlotError, .lastSlot)
        }
    }

    func testRestoringRejectsReusedSlotIDWithoutChangingConfig() throws {
        let original = SwitcherConfig.default
        let removal = try original.removingSlotWithReceipt(.chinese)
        XCTAssertThrowsError(try original.restoringSlot(removal.removed)) { error in
            XCTAssertEqual(error as? SlotError, .slotAlreadyExists(.chinese))
        }
        XCTAssertEqual(original, .default)
    }

    func testRestoringRejectsPreferredSourceOwnedByAnotherSlot() throws {
        let original = SwitcherConfig.default
        let removal = try original.removingSlotWithReceipt(.chinese)
        var changed = removal.config
        let preferred = try XCTUnwrap(removal.removed.preference?.preferredIDs.first)
        changed.pinInputSourceID(preferred, for: .english)
        let snapshot = changed
        XCTAssertThrowsError(try changed.restoringSlot(removal.removed)) { error in
            XCTAssertEqual(error as? SlotError, .sourceAlreadyUsed)
        }
        XCTAssertEqual(changed, snapshot)
    }

    func testRestoringAllowsPreferredSourceInAnotherSlotsLegacyHistory() throws {
        let original = SwitcherConfig.default
        let removal = try original.removingSlotWithReceipt(.chinese)
        var changed = removal.config
        let preferred = try XCTUnwrap(removal.removed.preference?.preferredIDs.first)
        changed.inputSources["english"]?.preferredIDs.append(preferred)
        let restored = try changed.restoringSlot(removal.removed)
        XCTAssertEqual(restored.config.preference(for: .chinese), original.preference(for: .chinese))
        XCTAssertEqual(restored.config.preference(for: .english), changed.preference(for: .english))
        XCTAssertEqual(restored.skippedBindings, [])
    }

    func testRestoringSkipsOccupiedTriggerButRestoresSlotAndOtherBindings() throws {
        var original = SwitcherConfig.default
        original.switchIndicatorCustomRoleColorHexes["chinese"] = "#123456"
        original.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("command+k"), action: .switchInputSource(.chinese)))
        original.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("option+l"), action: .switchInputSource(.chinese), enabled: false))
        let removal = try original.removingSlotWithReceipt(.chinese)
        var changed = removal.config
        let occupant = KeyBinding(trigger: try ShortcutParser.parse("double-right-command"), action: .sendKey(try ShortcutParser.parse("a")))
        changed.bindings.append(occupant)
        let snapshot = changed

        let restored = try changed.restoringSlot(removal.removed)
        XCTAssertEqual(restored.config.slots, original.slots)
        XCTAssertEqual(restored.config.inputSources, original.inputSources)
        XCTAssertEqual(restored.config.switchIndicatorCustomRoleColorHexes, original.switchIndicatorCustomRoleColorHexes)
        XCTAssertEqual(restored.skippedBindings, [removal.removed.bindings[0]])
        XCTAssertEqual(restored.config.bindings, [original.bindings[0], original.bindings[2], original.bindings[3], original.bindings[4], occupant])
        XCTAssertEqual(changed, snapshot)
    }

    func testRestoringSkipsChordOccupiedBySlotOrRemap() throws {
        var original = SwitcherConfig.default
        let chord = try ShortcutParser.parse("command+option+k")
        original.upsertSwitchBinding(trigger: chord, role: .chinese)
        let removal = try original.removingSlotWithReceipt(.chinese)
        for action in [BindingAction.switchInputSource(.english), .sendKey(try ShortcutParser.parse("a"))] {
            var changed = removal.config
            var reorderedChord = chord
            reorderedChord.modifiers.reverse()
            let occupant = KeyBinding(trigger: reorderedChord, action: action)
            changed.bindings.append(occupant)
            let restored = try changed.restoringSlot(removal.removed)
            XCTAssertEqual(restored.config.slots, original.slots)
            XCTAssertEqual(restored.config.bindings, changed.bindings)
            XCTAssertEqual(restored.skippedBindings, removal.removed.bindings)
        }
    }

    func testRestoringPreservesDisabledBindingsAndIgnoresDisabledOccupants() throws {
        for removedEnabled in [false, true] {
            var original = SwitcherConfig.default
            original.bindings[1].enabled = removedEnabled
            let removal = try original.removingSlotWithReceipt(.chinese)
            var changed = removal.config
            let occupant = KeyBinding(trigger: original.bindings[1].trigger, action: .sendKey(try ShortcutParser.parse("a")), enabled: !removedEnabled)
            changed.bindings.append(occupant)
            let restored = try changed.restoringSlot(removal.removed)
            XCTAssertEqual(restored.skippedBindings, [])
            XCTAssertEqual(restored.config.bindings, original.bindings + [occupant])
        }
    }

    func testRestoringClampsSavedPositionsAfterInterveningRemovals() throws {
        let original = SwitcherConfig.default
        let removal = try original.removingSlotWithReceipt(.japanese)
        let changed = try removal.config.removingSlot(.chinese)
        let restored = try changed.restoringSlot(removal.removed)
        XCTAssertEqual(restored.config.slots.map(\.id), [.english, .japanese])
        XCTAssertEqual(restored.config.bindings, [original.bindings[0], original.bindings[2]])
        XCTAssertEqual(restored.skippedBindings, [])
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
        XCTAssertEqual(moved.bindings, result.config.bindings)
        XCTAssertEqual(moved.inputSources, result.config.inputSources)
        XCTAssertEqual(renamed.bindings, moved.bindings)
        XCTAssertEqual(renamed.inputSources, moved.inputSources)
        XCTAssertEqual(renamed.slots.map(\.tintHex), moved.slots.map(\.tintHex))
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
        XCTAssertFalse(removed.bindings.contains { $0.action.type == .switchInputSource && $0.action.role == .chinese })
        XCTAssertEqual(removed.bindings, config.bindings.filter { $0.action.role != .chinese })
        let reloaded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(removed))
        XCTAssertEqual(reloaded.slots.map(\.id), [.english, .japanese])
        XCTAssertEqual(reloaded.bindings, removed.bindings)
        XCTAssertThrowsError(try removed.removingSlot(.chinese))
        let last = try removed.removingSlot(.japanese)
        XCTAssertThrowsError(try last.removingSlot(.english))
    }

    func testRemovalOfDisabledBindingSurvivesRoundTrip() throws {
        var config = SwitcherConfig.default
        let index = try XCTUnwrap(config.bindings.firstIndex { $0.action.role == .chinese })
        config.bindings[index].enabled = false
        let removed = try config.removingSlot(.chinese)
        XCTAssertFalse(removed.bindings.contains { $0.action.type == .switchInputSource && $0.action.role == .chinese })
        let reloaded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(removed))
        XCTAssertEqual(reloaded.slots.map(\.id), [.english, .japanese])
        XCTAssertEqual(reloaded.bindings, config.bindings.filter { $0.action.role != .chinese })
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
        config.inputSources["japanese"]?.preferredIDs.append(abc.id)
        config.slots = [config.slots[2], config.slots[1], config.slots[0]]
        for role in InputRole.legacy {
            XCTAssertEqual(InputSourceMatcher.bestMatch(for: role, sources: [abc], config: config), abc)
        }
        XCTAssertEqual(config.duplicateSlotIDs(for: .english, sources: [abc]), [.japanese, .chinese])
        XCTAssertEqual(config.duplicateSlotIDs(for: .chinese, sources: [abc]), [.japanese, .english])
        XCTAssertEqual(config.duplicateSlotIDs(for: .japanese, sources: [abc]), [.chinese, .english])
        XCTAssertEqual(SwitcherConfig.default.duplicateSlotIDs(for: .japanese, sources: [abc]), [])
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

    func testChordConflictIdentifiesOtherSlotAndRemapWithoutChangingBindings() throws {
        let chord = try ShortcutParser.parse("command+option+k")
        let slotBinding = KeyBinding(trigger: chord, action: .switchInputSource(.chinese))
        var config = SwitcherConfig.default
        config.bindings.append(slotBinding)
        let original = config

        XCTAssertEqual(config.conflictingBinding(for: chord, excluding: .english), slotBinding)
        XCTAssertNil(config.conflictingBinding(for: chord, excluding: .chinese))
        XCTAssertEqual(config, original)

        let remap = KeyBinding(trigger: chord, action: .sendKey(try ShortcutParser.parse("a")))
        config.bindings = [remap]
        XCTAssertEqual(config.conflictingBinding(for: chord, excluding: .english), remap)
        XCTAssertEqual(config.conflictingBinding(for: chord, excluding: .chinese), remap)
        XCTAssertNil(config.conflictingBinding(for: try ShortcutParser.parse("command+k"), excluding: .english))
        config.bindings[0].enabled = false
        XCTAssertNil(config.conflictingBinding(for: chord, excluding: .english))
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

    func testDetectionOfEnglishAndKoreanDoesNotSeedLegacySlots() {
        let sources = [source("com.apple.keylayout.ABC", "en"), source()]
        let config = SwitcherConfig.detected(from: sources)
        XCTAssertEqual(config.slots.map(\.id.rawValue), ["english", "korean"])
        XCTAssertEqual(config.slots.map(\.name), ["English", "Korean"])
        XCTAssertEqual(config.slots.map(\.tintHex), Array(SlotPalette.colors.prefix(2)))
        XCTAssertNil(config.slot(.chinese))
        XCTAssertNil(config.inputSources["chinese"])
        XCTAssertEqual(config.preference(for: .english), RoleInputSourcePreference(preferredIDs: [sources[0].id], fallbackLanguage: "en"))
        XCTAssertEqual(config.preference(for: InputRole(rawValue: "korean")), RoleInputSourcePreference(preferredIDs: [sources[1].id], fallbackLanguage: "ko"))
        XCTAssertEqual(config.bindings.map(\.trigger.keyName), ["left-command", "right-command"])
        XCTAssertEqual(config.version, SwitcherConfig.currentVersion)
    }

    func testDetectionOfEnglishGermanAndRussianInSystemOrder() {
        let config = SwitcherConfig.detected(from: [source("com.apple.keylayout.ABC", "en"), source("de.one", "de"), source("ru.one", "ru")])
        XCTAssertEqual(config.slots.map(\.id.rawValue), ["english", "german", "russian"])
        XCTAssertEqual(config.slots.map(\.name), ["English", "German", "Russian"])
        XCTAssertEqual(config.bindings.map(\.trigger.keyName), ["left-command", "right-command", "left-option"])
        let reversed = SwitcherConfig.detected(from: [source("ru.one", "ru"), source("de.one", "de"), source("com.apple.keylayout.ABC", "en")])
        XCTAssertEqual(reversed.slots.map(\.id.rawValue), ["russian", "german", "english"])
    }

    func testDetectionAssignsFiveOneShotsAndLeavesSixthUnbound() {
        let sources = ["en", "de", "ru", "ko", "ja", "zh"].map { source("source.\($0)", $0) }
        for count in [5, 6] {
            let config = SwitcherConfig.detected(from: Array(sources.prefix(count)))
            XCTAssertEqual(config.slots.count, count)
            XCTAssertEqual(config.inputSources.count, count)
            XCTAssertEqual(config.bindings.map(\.trigger.keyName), ["left-command", "right-command", "left-option", "right-option", "left-control"])
            XCTAssertTrue(config.bindings.allSatisfy { $0.enabled && $0.trigger.kind == .oneShotModifier })
            XCTAssertEqual(config.bindings.map(\.action.role), config.slots.prefix(5).map { Optional($0.id) })
        }
    }

    func testDetectionKeepsFirstSourcePerPrimaryLanguageIncludingChineseVariants() {
        var multilingual = source("first", "de-DE")
        multilingual.languages = ["de-DE", "en"]
        let config = SwitcherConfig.detected(from: [multilingual, source("de.second", "de"), source("zh.first", "zh_Hant"), source("zh.second", "zh-Hans"), source("en.first", "en-US"), source("en.second", "en")])
        XCTAssertEqual(config.slots.map(\.id.rawValue), ["german", "chinese", "english"])
        XCTAssertEqual(config.slots.map { config.preference(for: $0.id).preferredIDs }, [["first"], ["zh.first"], ["en.first"]])
        XCTAssertEqual(config.preference(for: .chinese).fallbackLanguage, "zh")
    }

    func testDetectionSkipsAuxiliaryNonselectableAndInvalidSources() {
        var nonselectable = source("disabled", "en")
        nonselectable.isSelectCapable = false
        let config = SwitcherConfig.detected(from: [source("com.apple.CharacterPaletteIM", "en"), source("com.apple.PressAndHold", "en"), source("com.apple.dictation", "en"), nonselectable, source("  ", "en"), source("valid", "en")])
        XCTAssertEqual(config.slots.map(\.id), [.english])
        XCTAssertEqual(config.preference(for: .english).preferredIDs, ["valid"])
        XCTAssertEqual(SwitcherConfig.detected(from: [nonselectable]), .default)
    }

    func testDetectionFallsBackToDefaultForEmptyOrMissingPrimaryLanguages() {
        XCTAssertEqual(SwitcherConfig.detected(from: []), .default)
        var noLanguages = source("none")
        noLanguages.languages = []
        var emptyFirst = source("empty")
        emptyFirst.languages = ["  ", "en"]
        XCTAssertEqual(SwitcherConfig.detected(from: [noLanguages, emptyFirst]), .default)
        let config = SwitcherConfig.detected(from: [noLanguages, emptyFirst, source()])
        XCTAssertEqual(config.slots.map(\.id.rawValue), ["korean"])
    }

    func testDetectionWithRealShapedEnglishChineseJapaneseFixture() {
        let sources = [
            InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en", "de"], isSelectCapable: true),
            InputSourceInfo(id: "com.tencent.inputmethod.wetype.pinyin", localizedName: "微信输入法", languages: ["zh-Hans"], isSelectCapable: true),
            InputSourceInfo(id: "dev.ensan.inputmethod.azooKeyMac.Japanese", localizedName: "azooKey (日本語)", languages: ["ja"], isSelectCapable: true),
            InputSourceInfo(id: "com.apple.CharacterPaletteIM", localizedName: "Emoji & Symbols", languages: [], isSelectCapable: true),
        ]
        let config = SwitcherConfig.detected(from: sources)
        XCTAssertEqual(config.slots, SwitchSlot.legacyDefaults)
        XCTAssertEqual(config.slots.map { config.preference(for: $0.id).preferredIDs }, sources.prefix(3).map { [$0.id] })
        XCTAssertEqual(config.slots.map { config.preference(for: $0.id).fallbackLanguage }, ["en", "zh", "ja"])
        XCTAssertEqual(config.bindings.map(\.trigger.keyName), ["left-command", "right-command", "left-option"])
        // This machine currently enumerates Japanese before Chinese; detection
        // must honor either order rather than imposing the legacy slot order.
        let systemOrder = SwitcherConfig.detected(from: [sources[0], sources[2], sources[1], sources[3]])
        XCTAssertEqual(systemOrder.slots.map(\.id.rawValue), ["english", "japanese", "chinese"])
    }

    func testRebuildingReplacesAllSlotDataPreservesGlobalSettingsAndIsPure() throws {
        var original = try SwitcherConfig.default.addingSlot(for: source("old.ko")).config
        original.showSwitchIndicator = false
        original.switchIndicatorSize = .large
        original.switchIndicatorScale = 1.23
        original.switchIndicatorColorStyle = .custom
        original.switchIndicatorContentStyle = .textOnly
        original.switchIndicatorCustomColorHex = "#123456"
        original.switchIndicatorCustomRoleColorHexes = ["english": "#ABCDEF", "korean": "#654321"]
        original.inputSources["orphan"] = RoleInputSourcePreference(preferredIDs: ["old.orphan"])
        original.bindings.append(KeyBinding(trigger: try ShortcutParser.parse("right-option"), action: .sendKey(try ShortcutParser.parse("a"))))
        let snapshot = original
        for sources in [[source("new.en", "en"), source("new.de", "de")], []] {
            let detected = SwitcherConfig.detected(from: sources)
            let rebuilt = original.rebuildingSlots(from: sources)
            var expected = snapshot
            expected.slots = detected.slots
            expected.bindings = detected.bindings
            expected.inputSources = detected.inputSources
            expected.switchIndicatorCustomRoleColorHexes = [:]
            expected.version = SwitcherConfig.currentVersion
            XCTAssertEqual(rebuilt, expected)
            XCTAssertEqual(original, snapshot)
        }
    }

    func testLiveKeysFollowRealBindingsInsteadOfDefaults() throws {
        var config = SwitcherConfig.default
        let rightShift = KeyTrigger(kind: .oneShotModifier, keyCode: 60, keyName: "right-shift")
        config.upsertSwitchBinding(trigger: rightShift, role: .japanese)

        XCTAssertEqual(config.slotID(forOneShotKeyName: "left-command"), .english)
        XCTAssertEqual(config.slotID(forOneShotKeyName: "right-command"), .chinese)
        XCTAssertEqual(config.slotID(forOneShotKeyName: "right-shift"), .japanese)
        XCTAssertNil(config.slotID(forOneShotKeyName: "left-option"))
        XCTAssertTrue(config.chordTriggers.isEmpty)
    }

    func testLiveKeysListChordsAndIgnoreDisabledOrOrphanedBindings() throws {
        var config = SwitcherConfig.default
        XCTAssertEqual(config.chordTriggers.map(\.slot), [.japanese])
        XCTAssertEqual(config.chordTriggers.first?.trigger.displayName, "option+j")

        var doubleTap = KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option")
        doubleTap.gesture = .doubleTap
        config.upsertSwitchBinding(trigger: doubleTap, role: .japanese)
        XCTAssertEqual(config.slotID(forOneShotKeyName: "left-option"), .japanese)

        config.bindings = config.bindings.map { binding in
            var copy = binding
            if copy.action.role == .english { copy.enabled = false }
            return copy
        }
        XCTAssertNil(config.slotID(forOneShotKeyName: "left-command"))

        let removed = try config.removingSlot(.chinese)
        XCTAssertNil(removed.slotID(forOneShotKeyName: "right-command"))
    }
}
