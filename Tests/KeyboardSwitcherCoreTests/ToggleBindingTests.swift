import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct ToggleBindingTests {
    private func trigger(_ text: String) throws -> KeyTrigger {
        try ShortcutParser.parse(text)
    }

    @Test("setting a toggle adds one binding naming both slots and keeps the slot bindings")
    func setsTheToggle() throws {
        let config = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)

        #expect(config.toggleBinding?.action == .toggleSlots(.english, .chinese))
        #expect(config.toggleSlots.map { [$0.0, $0.1] } == [.english, .chinese])
        #expect(config.bindings.filter { $0.action.type == .switchInputSource } == SwitcherConfig.default.bindings)
    }

    @Test("a second toggle replaces the first, and nil removes it")
    func replacesAndRemoves() throws {
        let first = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)
        let second = try first.replacingToggleBinding(with: trigger("double-right-option"), slots: .chinese, .japanese)

        #expect(second.bindings.filter { $0.action.type == .toggleSlots }.count == 1)
        #expect(second.toggleBinding?.action == .toggleSlots(.chinese, .japanese))
        #expect(try second.replacingToggleBinding(with: nil, slots: .english, .chinese).toggleBinding == nil)
    }

    @Test("a key one of the two slots has moves to the toggle")
    func takesOverAKeyOfItsOwnSlots() throws {
        // The legacy defaults tap Left Command for English.
        let leftCommand = try trigger("left-command")
        #expect(SwitcherConfig.default.toggleTakeover(of: leftCommand, slots: .english, .chinese)?.action.role == .english)

        let config = try SwitcherConfig.default.replacingToggleBinding(with: leftCommand, slots: .english, .chinese)

        #expect(config.toggleBinding?.trigger == leftCommand)
        #expect(!config.bindings.contains { $0.action.role == .english && $0.trigger == leftCommand })
    }

    @Test("a key another slot has, the same slot twice, an unknown slot and macOS's own shortcut are refused")
    func refusals() throws {
        // Right Command belongs to Chinese in the legacy defaults, which this toggle does not name.
        let rightCommand = try trigger("right-command")
        #expect(SwitcherConfig.default.toggleTakeover(of: rightCommand, slots: .english, .japanese) == nil)
        #expect(throws: ToggleBindingError.self) {
            try SwitcherConfig.default.replacingToggleBinding(with: rightCommand, slots: .english, .japanese)
        }
        #expect(throws: ToggleBindingError.sameSlot) {
            try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .english)
        }
        #expect(throws: ToggleBindingError.unknownSlot(InputRole(rawValue: "korean"))) {
            try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, InputRole(rawValue: "korean"))
        }
        #expect(throws: ToggleBindingError.reservedByMacOS(try trigger("control+space"))) {
            try SwitcherConfig.default.replacingToggleBinding(with: trigger("control+space"), slots: .english, .chinese)
        }
    }

    @Test("the CLI's bind takes the trigger from the slot that had it")
    func upsertDisplaces() throws {
        var config = SwitcherConfig.default

        let displaced = try config.upsertToggleBinding(trigger: trigger("left-command"), slots: .english, .chinese)

        #expect(displaced.map(\.action.role) == [.english])
        #expect(config.toggleBinding?.trigger == (try trigger("left-command")))
    }

    @Test("removing a slot removes the toggle that names it, and undo brings both back")
    func slotRemoval() throws {
        let config = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)

        let (removed, receipt) = try config.removingSlotWithReceipt(.chinese)
        #expect(removed.toggleBinding == nil)

        let (restored, skipped) = try removed.restoringSlot(receipt)
        #expect(skipped.isEmpty)
        #expect(restored.toggleBinding?.action == .toggleSlots(.english, .chinese))
    }

    @Test("undo leaves the toggle out when its other slot is gone too")
    func restoreWithoutTheOtherSlot() throws {
        let config = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)
        let (withoutChinese, receipt) = try config.removingSlotWithReceipt(.chinese)
        let withoutBoth = try withoutChinese.removingSlot(.english)

        let (restored, skipped) = try withoutBoth.restoringSlot(receipt)

        #expect(restored.toggleBinding == nil)
        #expect(skipped.map(\.binding.action.type) == [.toggleSlots])
    }

    @Test("a slot reached only through the toggle counts as bound in the setup guide")
    func setupGuideCountsToggleSlots() throws {
        var config = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)
        config.bindings.removeAll { $0.action.type == .switchInputSource && $0.action.role != .japanese }

        let state = SetupGuideInput(config: config, sources: [], accessibilityGranted: true, inputMonitoringGranted: true,
                                    listenerRunning: true, hasConfirmedSlots: true)

        #expect(state.boundSlotCount == 3)
        #expect(!SetupUnboundSlots(config: config).hasUnboundSlots)
        #expect(SetupTriggerFingerprint(slotID: .english, config: config, sources: [
            InputSourceInfo(id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true),
        ])?.triggers == [try trigger("option+t")])
    }

    @Test("an older file without roles decodes, and a file without a toggle encodes no roles key")
    func compatibility() throws {
        let old = #"{"type":"switchInputSource","role":"english"}"#
        let action = try JSONDecoder().decode(BindingAction.self, from: Data(old.utf8))
        #expect(action == .switchInputSource(.english))
        #expect(!String(decoding: try JSONEncoder().encode(action), as: UTF8.self).contains("roles"))
    }

    @Test("the decision: the other slot from one of the two, the one used last from anywhere else")
    func decision() {
        let pick = { (current: InputRole?, recent: [InputRole]) in
            ToggleDecision.target(first: .english, second: .chinese, current: current, recentSlots: recent)
        }

        #expect(pick(.english, []) == .chinese)
        #expect(pick(.chinese, [.english]) == .english)
        #expect(pick(.japanese, [.japanese, .chinese, .english]) == .chinese)
        #expect(pick(nil, [.english]) == .english)
        #expect(pick(.japanese, []) == .english)
    }

    @Test("clearing the toggle gives a taken key back to its slot")
    func clearGivesBack() throws {
        let leftCommand = try trigger("left-command")
        let toggled = try SwitcherConfig.default.replacingToggleBinding(with: leftCommand, slots: .english, .chinese)
        #expect(toggled.toggleBinding?.action.takenFrom == .english)
        #expect(toggled.toggleGiveBack(of: toggled.toggleBinding).map { [$0.slot] } == [.english])

        let cleared = try toggled.replacingToggleBinding(with: nil, slots: .english, .chinese)

        #expect(cleared.toggleBinding == nil)
        #expect(cleared.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })
    }

    @Test("changing the pair keeps the key and where it came from; moving to another key gives it back")
    func pairChangeAndKeyChange() throws {
        let leftCommand = try trigger("left-command")
        let toggled = try SwitcherConfig.default.replacingToggleBinding(with: leftCommand, slots: .english, .chinese)

        let otherPair = try toggled.replacingToggleBinding(with: leftCommand, slots: .chinese, .japanese)
        #expect(otherPair.toggleBinding?.action.takenFrom == .english)

        let otherKey = try otherPair.replacingToggleBinding(with: trigger("option+t"), slots: .chinese, .japanese)
        #expect(otherKey.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })
        #expect(otherKey.toggleBinding?.action.takenFrom == nil)
    }

    @Test("a key that was free comes back to nobody, and an older toggle without takenFrom decodes")
    func noGiveBack() throws {
        let toggled = try SwitcherConfig.default.replacingToggleBinding(with: trigger("option+t"), slots: .english, .chinese)
        let cleared = try toggled.replacingToggleBinding(with: nil, slots: .english, .chinese)
        #expect(cleared.bindings == SwitcherConfig.default.bindings)

        let older = #"{"type":"toggleSlots","roles":["english","chinese"]}"#
        #expect(try JSONDecoder().decode(BindingAction.self, from: Data(older.utf8)) == .toggleSlots(.english, .chinese))
    }

    @Test("removing the other slot of the pair gives the key back, and undo takes it back for the toggle")
    func slotRemovalGivesBack() throws {
        let leftCommand = try trigger("left-command")
        let toggled = try SwitcherConfig.default.replacingToggleBinding(with: leftCommand, slots: .english, .chinese)

        let (removed, receipt) = try toggled.removingSlotWithReceipt(.chinese)
        #expect(removed.toggleBinding == nil)
        #expect(removed.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })

        let (restored, skipped) = try removed.restoringSlot(receipt)
        #expect(skipped.isEmpty)
        #expect(restored.toggleBinding?.trigger == leftCommand)
        #expect(!restored.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })
    }

    @Test("the CLI records where the key came from and gives the old one back")
    func cliGivesBack() throws {
        let leftCommand = try trigger("left-command")
        var config = SwitcherConfig.default
        _ = try config.upsertToggleBinding(trigger: leftCommand, slots: .english, .chinese)
        #expect(config.toggleBinding?.action.takenFrom == .english)

        _ = try config.upsertToggleBinding(trigger: trigger("option+t"), slots: .english, .chinese)

        #expect(config.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })
        #expect(config.toggleBinding?.action.takenFrom == nil)
    }

    @Test("the CLI remembers a key taken from a third slot and gives it back on clear")
    func cliThirdSlot() throws {
        var config = SwitcherConfig.default
        let optionJ = try trigger("option+j")  // Japanese in the legacy defaults
        _ = try config.upsertToggleBinding(trigger: optionJ, slots: .english, .chinese)
        #expect(config.toggleBinding?.action.takenFrom == .japanese)

        let cleared = try config.replacingToggleBinding(with: nil, slots: .english, .chinese)
        #expect(cleared.bindings.contains { $0.trigger == optionJ && $0.action == .switchInputSource(.japanese) })
    }

    @Test("undo keeps the given-back key when a newer toggle took the old one's place")
    func undoAfterNewerToggle() throws {
        let leftCommand = try trigger("left-command")
        let toggled = try SwitcherConfig.default.replacingToggleBinding(with: leftCommand, slots: .english, .chinese)
        let (removed, receipt) = try toggled.removingSlotWithReceipt(.chinese)
        let newer = try removed.replacingToggleBinding(with: trigger("right-shift"), slots: .english, .japanese)

        let (restored, skipped) = try newer.restoringSlot(receipt)

        #expect(skipped.map(\.binding.action.type) == [.toggleSlots])
        #expect(restored.toggleBinding?.trigger == (try trigger("right-shift")))
        #expect(restored.bindings.contains { $0.trigger == leftCommand && $0.action == .switchInputSource(.english) })
    }
}
