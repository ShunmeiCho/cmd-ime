import XCTest
@testable import KeyboardSwitcherCore

final class SlotTriggerCategoryTests: XCTestCase {
    private func trigger(_ text: String) throws -> KeyTrigger {
        try ShortcutParser.parse(text)
    }

    private func threeCategories() throws -> SwitcherConfig {
        try SwitcherConfig.default
            .replacingSwitchBinding(for: .english, category: .double, with: trigger("double-left-command"))
            .replacingSwitchBinding(for: .english, category: .shortcut, with: trigger("command+k"))
    }

    func testThreeCategoriesPersistAndIndependentClearSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        let original = try threeCategories()
        try store.save(original)
        let loaded = try store.loadOrRecover().config
        XCTAssertEqual(loaded, original)
        let cleared = try loaded.replacingSwitchBinding(for: .english, category: .double, with: nil)
        try store.save(cleared)
        let reloaded = try store.loadOrRecover().config
        XCTAssertNil(reloaded.binding(for: .english, category: .double))
        XCTAssertEqual(reloaded.binding(for: .english, category: .single), original.binding(for: .english, category: .single))
        XCTAssertEqual(reloaded.binding(for: .english, category: .shortcut), original.binding(for: .english, category: .shortcut))
    }

    func testRuntimeSharedPhysicalKeyStillWaitsBeforeSingleAndSelectsDouble() throws {
        let single = try trigger("left-command")
        let config = try SwitcherConfig.default.replacingSwitchBinding(
            for: .chinese, category: .double, with: trigger("double-left-command"))
        XCTAssertNotNil(config.binding(for: .english, category: .single))
        XCTAssertNotNil(config.binding(for: .chinese, category: .double))
        var state = OneShotModifierState()
        state.modifierDown(single)
        XCTAssertEqual(state.modifierUp(single, hasDoubleTapBinding: true), .wait)
        XCTAssertEqual(state.flushPendingSingleTap(), single)
        state.modifierDown(single)
        XCTAssertEqual(state.modifierUp(single, hasDoubleTapBinding: true), .wait)
        state.modifierDown(single)
        XCTAssertEqual(state.modifierUp(single, hasDoubleTapBinding: true), .trigger(try trigger("double-left-command")))
        XCTAssertEqual(OneShotModifierState.doubleTapWindow, 0.22)
    }

    func testThreeCategoriesCoexistAndRoundTripWithoutNewJSONFields() throws {
        let config = try threeCategories()
        for category in SlotTriggerCategory.allCases {
            XCTAssertNotNil(config.binding(for: .english, category: category))
        }
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(SwitcherConfig.self, from: data), config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bindings = try XCTUnwrap(json["bindings"] as? [[String: Any]])
        XCTAssertTrue(bindings.allSatisfy { Set($0.keys) == ["trigger", "action", "enabled"] })
    }

    func testReplaceAndClearOnlySelectedCategoryPreservingOtherData() throws {
        var config = try threeCategories()
        config.bindings.append(KeyBinding(trigger: try trigger("option+l"), action: .sendKey(try trigger("a")), enabled: false))
        config.bindings.append(KeyBinding(trigger: try trigger("control+l"), action: .sendKey(try trigger("b"))))
        let snapshot = config
        for category in SlotTriggerCategory.allCases {
            let replacement = try trigger(category == .single ? "left-option" : category == .double ? "double-left-option" : "control+k")
            let updated = try config.replacingSwitchBinding(for: .english, category: category, with: replacement)
            var expected = config
            let index = try XCTUnwrap(expected.bindings.firstIndex { $0.action.role == .english && category.matches($0.trigger) })
            expected.bindings[index].trigger = replacement
            XCTAssertEqual(updated, expected)
            expected.bindings.remove(at: index)
            XCTAssertEqual(try updated.replacingSwitchBinding(for: .english, category: category, with: nil), expected)
        }
        XCTAssertEqual(config, snapshot)
    }

    func testSamePhysicalKeyDifferentGesturesAcrossRolesAreAllowedButSameGestureConflicts() throws {
        let original = SwitcherConfig.default
        let double = try trigger("double-left-command")
        let updated = try original.replacingSwitchBinding(for: .chinese, category: .double, with: double)
        XCTAssertEqual(updated.binding(for: .english, category: .single), original.bindings[0])
        XCTAssertEqual(updated.binding(for: .chinese, category: .double)?.trigger, double)
        XCTAssertThrowsError(try updated.replacingSwitchBinding(for: .japanese, category: .double, with: double)) { error in
            XCTAssertEqual(error as? SlotTriggerCategoryError, .conflictingBinding(updated.binding(for: .chinese, category: .double)!))
        }
        XCTAssertThrowsError(try original.replacingSwitchBinding(for: .chinese, category: .single, with: original.bindings[0].trigger))
        XCTAssertEqual(original, .default)
    }

    func testWrongKindAndGestureAndUnknownSlotAreRejected() throws {
        let config = SwitcherConfig.default
        for (category, text) in [(SlotTriggerCategory.single, "command+k"), (.single, "double-left-option"), (.double, "left-option"), (.shortcut, "left-option"), (.shortcut, "a")] {
            XCTAssertThrowsError(try config.replacingSwitchBinding(for: .english, category: category, with: trigger(text))) { error in
                XCTAssertEqual(error as? SlotTriggerCategoryError, .mismatchedTrigger(category))
            }
        }
        let missing = InputRole(rawValue: "missing")
        XCTAssertThrowsError(try config.replacingSwitchBinding(for: missing, category: .single, with: nil)) { error in
            XCTAssertEqual(error as? SlotError, .unknownSlot(missing))
        }
    }

    func testExplicitReplacementEnablesItsCategoryAndDisabledOccupantsDoNotReserveTriggers() throws {
        var config = SwitcherConfig.default
        config.bindings[0].enabled = false
        XCTAssertNil(config.binding(for: .english, category: .single))
        let updated = try config.replacingSwitchBinding(for: .english, category: .single, with: trigger("left-option"))
        XCTAssertTrue(updated.bindings[0].enabled)
        XCTAssertNotNil(updated.binding(for: .english, category: .single))
        XCTAssertNoThrow(try config.replacingSwitchBinding(for: .chinese, category: .single, with: trigger("left-command")))
    }

    func testRemapConflictDoesNotStealBindingAndModifierAliasIsRejected() throws {
        var config = SwitcherConfig.default
        let chord = try trigger("command+k")
        let remap = KeyBinding(trigger: chord, action: .sendKey(try trigger("a")))
        config.bindings.append(remap)
        let snapshot = config
        XCTAssertThrowsError(try config.replacingSwitchBinding(for: .english, category: .shortcut, with: chord)) { error in
            XCTAssertEqual(error as? SlotTriggerCategoryError, .conflictingBinding(remap))
        }
        var alias = config.bindings[0].trigger
        alias.keyCode = 999
        XCTAssertThrowsError(try config.replacingSwitchBinding(for: .chinese, category: .single, with: alias))
        XCTAssertEqual(config, snapshot)
    }

    func testLegacyDuplicateCategoryIsCollapsedWithoutRemovingOtherCategories() throws {
        var config = try threeCategories()
        config.bindings.insert(KeyBinding(trigger: try trigger("left-option"), action: .switchInputSource(.english), enabled: false), at: 0)
        let updated = try config.replacingSwitchBinding(for: .english, category: .single, with: trigger("left-control"))
        XCTAssertTrue(updated.bindings[0].enabled)
        XCTAssertEqual(updated.bindings.filter { $0.action.role == .english }.count, 3)
        XCTAssertEqual(updated.binding(for: .english, category: .double), config.binding(for: .english, category: .double))
    }
}
