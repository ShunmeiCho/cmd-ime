import XCTest
@testable import KeyboardSwitcherCore

final class ShortcutParserTests: XCTestCase {
    func testParsesOneShotLeftCommand() throws {
        let trigger = try ShortcutParser.parse("left-command")

        XCTAssertEqual(trigger.kind, .oneShotModifier)
        XCTAssertEqual(trigger.keyCode, 55)
        XCTAssertEqual(trigger.keyName, "left-command")
        XCTAssertTrue(trigger.modifiers.isEmpty)
    }

    func testParsesSidePrefixedChordModifiers() throws {
        for modifier in ["command", "option", "control", "shift"] {
            for side in ["left", "right"] {
                let name = "\(side)-\(modifier)+j"
                let trigger = try ShortcutParser.parse(name)
                XCTAssertEqual(trigger.kind, .keyPress)
                XCTAssertEqual(trigger.displayName, name)
            }
        }
    }

    func testParsesSidePrefixedModifierAliases() throws {
        let aliases = ["cmd": "command", "meta": "command", "opt": "option", "alt": "option", "ctrl": "control", "ctl": "control"]
        for (alias, modifier) in aliases {
            for side in ["left", "right"] {
                XCTAssertEqual(try ShortcutParser.parse("\(side)-\(alias)+j").displayName, "\(side)-\(modifier)+j")
            }
        }
        XCTAssertEqual(try ShortcutParser.parse("right-cmd+shift+k").displayName, "right-command+shift+k")
    }

    func testSidedChordDisplayNameRoundTrips() throws {
        let trigger = try ShortcutParser.parse("right-shift+left-option+right-cmd+k")
        XCTAssertEqual(trigger.displayName, "right-command+left-option+right-shift+k")
        XCTAssertEqual(try ShortcutParser.parse(trigger.displayName), trigger)
    }

    func testRejectsOppositeSidesOfDuplicateModifier() {
        XCTAssertThrowsError(try ShortcutParser.parse("left-option+right-option+j")) { error in
            XCTAssertEqual(error as? ShortcutParserError, .duplicateModifier("right-option"))
        }
        XCTAssertThrowsError(try ShortcutParser.parse("right-alt+option+j")) { error in
            XCTAssertEqual(error as? ShortcutParserError, .duplicateModifier("option"))
        }
    }

    func testSidedAndEitherSideChordsHaveDistinctEqualityAndHashing() throws {
        let triggers = try ["left-option+j", "right-option+j", "option+j"].map(ShortcutParser.parse)
        XCTAssertEqual(Set(triggers).count, 3)
        var config = SwitcherConfig.default
        for (trigger, slot) in zip(triggers, [InputRole.english, .chinese, .japanese]) {
            config.upsertSwitchBinding(trigger: trigger, role: slot)
        }
        for (trigger, slot) in zip(triggers, [InputRole.english, .chinese, .japanese]) {
            XCTAssertEqual(config.bindings.first { $0.trigger == trigger }?.action.role, slot)
        }
    }

    func testRejectsSidesOnLatchingModifiers() {
        for shortcut in ["left-fn+j", "right-caps-lock+j"] {
            XCTAssertThrowsError(try ShortcutParser.parse(shortcut)) { error in
                XCTAssertEqual(error as? ShortcutParserError, .unknownKey(String(shortcut.dropLast(2))))
            }
        }
    }

    func testSidePrefixedLoneModifiersKeepOneShotParsing() throws {
        for name in ["left-command", "right-cmd", "left-option", "right-alt", "left-control", "right-ctrl", "left-shift", "right-shift"] {
            let trigger = try ShortcutParser.parse(name)
            XCTAssertEqual(trigger.kind, .oneShotModifier)
            XCTAssertTrue(trigger.modifiers.isEmpty)
            XCTAssertEqual(try ShortcutParser.parse(trigger.displayName), trigger)
        }
    }

    func testTriggerInitializerDropsInvalidModifierSides() {
        let trigger = KeyTrigger(
            kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option, .fn, .capsLock],
            modifierSides: [.option: .left, .command: .right, .fn: .left, .capsLock: .right]
        )
        XCTAssertEqual(trigger.modifierSides, [.option: .left])
        let oneShot = KeyTrigger(
            kind: .oneShotModifier, keyCode: 55, keyName: "left-command", modifiers: [.command],
            modifierSides: [.command: .left]
        )
        XCTAssertTrue(oneShot.modifierSides.isEmpty)
    }

    func testEitherSideChordHasEmptyModifierSides() throws {
        XCTAssertTrue(try ShortcutParser.parse("option+j").modifierSides.isEmpty)
    }

    func testParsesOptionJShortcut() throws {
        let trigger = try ShortcutParser.parse("option+j")

        XCTAssertEqual(trigger.kind, .keyPress)
        XCTAssertEqual(trigger.keyCode, 38)
        XCTAssertEqual(trigger.keyName, "j")
        XCTAssertEqual(trigger.modifiers, [.option])
    }

    func testParsesDoubleTapModifierShortcut() throws {
        let trigger = try ShortcutParser.parse("double-left-command")

        XCTAssertEqual(trigger.kind, .oneShotModifier)
        XCTAssertEqual(trigger.gesture, .doubleTap)
        XCTAssertEqual(trigger.keyCode, 55)
    }

    func testParsesSideSpecificShiftOneShotShortcut() throws {
        let trigger = try ShortcutParser.parse("right-shift")

        XCTAssertEqual(trigger.kind, .oneShotModifier)
        XCTAssertEqual(trigger.keyCode, 60)
        XCTAssertEqual(trigger.keyName, "right-shift")
    }

    func testParsesCommandShiftSpaceShortcut() throws {
        let trigger = try ShortcutParser.parse("cmd+shift+space")

        XCTAssertEqual(trigger.keyCode, 49)
        XCTAssertEqual(trigger.modifiers, [.command, .shift])
    }

    func testFlagsMacInputSourceShortcutsAsReserved() throws {
        let previousInputSource = try ShortcutParser.parse("control+space")
        let nextInputSource = try ShortcutParser.parse("control+option+space")

        XCTAssertTrue(previousInputSource.isReserved(by: MacInputSourceShortcuts.defaults))
        XCTAssertTrue(nextInputSource.isReserved(by: MacInputSourceShortcuts.defaults))
        XCTAssertFalse(try ShortcutParser.parse("command+shift+space").isReserved(by: MacInputSourceShortcuts.defaults))
    }

    func testRejectsModifierOnlyShortcutWithoutSide() {
        XCTAssertThrowsError(try ShortcutParser.parse("command")) { error in
            XCTAssertEqual(error as? ShortcutParserError, .missingKey("command"))
        }
    }

    func testCapsLockIsNoLongerAOneShotTrigger() {
        // Caps Lock is a latch, not a momentary press, so it is intentionally not
        // offered as a one-shot trigger. It now parses as a modifier-only token.
        XCTAssertThrowsError(try ShortcutParser.parse("caps-lock")) { error in
            XCTAssertEqual(error as? ShortcutParserError, .missingKey("caps-lock"))
        }
    }
}
