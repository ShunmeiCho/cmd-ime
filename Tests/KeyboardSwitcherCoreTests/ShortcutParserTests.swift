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

        XCTAssertTrue(previousInputSource.isReservedMacInputSourceShortcut)
        XCTAssertTrue(nextInputSource.isReservedMacInputSourceShortcut)
        XCTAssertFalse(try ShortcutParser.parse("command+shift+space").isReservedMacInputSourceShortcut)
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
