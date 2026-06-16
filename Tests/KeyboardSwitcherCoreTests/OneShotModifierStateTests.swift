import XCTest
@testable import KeyboardSwitcherCore

final class OneShotModifierStateTests: XCTestCase {
    func testSingleModifierTapTriggersOnRelease() {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        var state = OneShotModifierState()

        state.modifierDown(trigger)

        XCTAssertEqual(state.modifierUp(trigger), .trigger(trigger))
    }

    func testModifierChordDoesNotTriggerOnRelease() {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        var state = OneShotModifierState()

        state.modifierDown(trigger)
        state.keyDown(8)

        XCTAssertEqual(state.modifierUp(trigger), .wait)
    }

    func testAnyChordKeyCancelsOneShotModifier() {
        let triggers = [
            KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
            KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
            KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option"),
            KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option"),
            KeyTrigger(kind: .oneShotModifier, keyCode: 59, keyName: "left-control"),
        ]
        let chordKeyCodes = [0, 8, 9, 38, 49]

        for trigger in triggers {
            for chordKeyCode in chordKeyCodes {
                var state = OneShotModifierState()
                state.modifierDown(trigger)
                state.keyDown(chordKeyCode)

                XCTAssertEqual(
                    state.modifierUp(trigger),
                    .wait,
                    "\(trigger.keyName)+keyCode(\(chordKeyCode)) should not trigger one-shot action"
                )
            }
        }
    }

    func testSecondModifierKeyCancelsOneShotModifier() {
        let leftCommand = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        let rightCommand = KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command")
        var state = OneShotModifierState()

        state.modifierDown(leftCommand)
        state.modifierDown(rightCommand)

        XCTAssertEqual(state.modifierUp(leftCommand), .wait)
    }

    func testCancelClearsPendingModifier() {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        var state = OneShotModifierState()

        state.modifierDown(trigger)
        state.cancel()

        XCTAssertEqual(state.modifierUp(trigger), .wait)
    }

    func testDoubleTapModifierTriggersDoubleTapGesture() {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        var expected = trigger
        expected.gesture = .doubleTap
        var state = OneShotModifierState()

        state.modifierDown(trigger)
        XCTAssertEqual(state.modifierUp(trigger, hasDoubleTapBinding: true), .wait)
        state.modifierDown(trigger)

        XCTAssertEqual(state.modifierUp(trigger, hasDoubleTapBinding: true), .trigger(expected))
    }

    func testSingleTapFlushesWhenWaitingForPossibleDoubleTap() {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        var state = OneShotModifierState()

        state.modifierDown(trigger)
        XCTAssertEqual(state.modifierUp(trigger, hasDoubleTapBinding: true), .wait)

        XCTAssertEqual(state.flushPendingSingleTap(), trigger)
    }
}
