import XCTest
@testable import KeyboardSwitcherCore

final class TriggerRecognizerTests: XCTestCase {
    func testRecordingWindowAcceptsThreeTenthsWhileDefaultRemainsSingle() throws {
        let key = try ShortcutParser.parse("left-command")
        var recording = TriggerRecognizer(doubleTapWindow: TriggerRecognizer.recordingDoubleTapWindow)
        var standard = TriggerRecognizer()
        _ = tap(&recording, key, at: 0)
        _ = tap(&standard, key, at: 0)
        XCTAssertEqual(tap(&recording, key, at: 0.3), .doubleTap(key.keyName))
        XCTAssertEqual(tap(&standard, key, at: 0.3), .tap(key.keyName))
        XCTAssertEqual(recording.draft?.gesture, .doubleTap)
        XCTAssertEqual(standard.draft?.gesture, .tap)
        XCTAssertEqual(TriggerRecognizer.recordingDoubleTapWindow, 0.45)
        XCTAssertEqual(OneShotModifierState.doubleTapWindow, 0.22)
    }

    func testRecordingWindowStillRejectsLateSecondTap() throws {
        let key = try ShortcutParser.parse("right-option")
        var state = TriggerRecognizer(doubleTapWindow: TriggerRecognizer.recordingDoubleTapWindow)
        _ = tap(&state, key, at: 0)
        XCTAssertEqual(tap(&state, key, at: 0.46), .tap(key.keyName))
    }

    func testParserDerivedPhysicalModifiersTapAndDoubleTap() throws {
        XCTAssertEqual(TriggerRecognizer.modifierTriggers.count, 8)
        for trigger in TriggerRecognizer.modifierTriggers.values {
            var state = TriggerRecognizer()
            XCTAssertEqual(tap(&state, trigger, at: 0), .tap(trigger.keyName))
            XCTAssertEqual(state.draft, trigger)
            XCTAssertEqual(tap(&state, trigger, at: 0.1), .doubleTap(trigger.keyName))
            XCTAssertEqual(state.draft?.gesture, .doubleTap)
            XCTAssertEqual(tap(&state, trigger, at: 0.2), .tap(trigger.keyName))
        }
    }

    func testLateOrDifferentTapStartsNewSequence() throws {
        let left = try ShortcutParser.parse("left-control")
        let right = try ShortcutParser.parse("right-control")
        var state = TriggerRecognizer()
        _ = tap(&state, left, at: 0)
        XCTAssertEqual(tap(&state, left, at: 1), .tap(left.keyName))
        XCTAssertEqual(tap(&state, right, at: 1.1), .tap(right.keyName))
    }

    func testOverlappingModifiersCannotTapIncludingSameFamily() throws {
        for second in ["right-control", "left-shift"] {
            let first = try ShortcutParser.parse("left-control")
            let other = try ShortcutParser.parse(second)
            var state = TriggerRecognizer()
            _ = state.keyDown(keyCode: first.keyCode, keyName: first.keyName, modifiers: [.control], timestamp: 0)
            _ = state.keyDown(keyCode: other.keyCode, keyName: other.keyName, modifiers: [.control, .shift], timestamp: 0.01)
            XCTAssertNil(state.keyUp(keyCode: other.keyCode, keyName: other.keyName, modifiers: [.control], timestamp: 0.02))
            XCTAssertNil(state.keyUp(keyCode: first.keyCode, keyName: first.keyName, modifiers: [], timestamp: 0.03))
            XCTAssertNil(state.draft)
        }
    }

    func testAggregateFlagsTrackBothSidesOnRelease() {
        var state = TriggerRecognizer()
        _ = state.flagsChanged(keyCode: 59, modifiers: [.control], timestamp: 0)
        _ = state.flagsChanged(keyCode: 62, modifiers: [.control], timestamp: 0.01)
        XCTAssertEqual(state.pressedModifierKeyCodes, [59, 62])
        XCTAssertNil(state.flagsChanged(keyCode: 59, modifiers: [.control], timestamp: 0.02))
        XCTAssertEqual(state.pressedModifierKeyCodes, [62])
        XCTAssertNil(state.flagsChanged(keyCode: 62, modifiers: [], timestamp: 0.03))
        XCTAssertTrue(state.pressedModifierKeyCodes.isEmpty)
        XCTAssertNil(state.draft)
    }

    func testInitialHeldAndRepeatedDownCannotRestoreTapCandidate() {
        var state = TriggerRecognizer(heldModifierKeyCodes: [59])
        _ = state.keyDown(keyCode: 59, keyName: "left-control", modifiers: [.control], timestamp: 0)
        XCTAssertNil(state.flagsChanged(keyCode: 59, modifiers: [], timestamp: 0.1))
        _ = state.flagsChanged(keyCode: 59, modifiers: [.control], timestamp: 1)
        _ = state.keyDown(keyCode: 0, keyName: "a", modifiers: [.control], timestamp: 1.01)
        _ = state.keyDown(keyCode: 59, keyName: "left-control", modifiers: [.control], timestamp: 1.02)
        XCTAssertNil(state.flagsChanged(keyCode: 59, modifiers: [], timestamp: 1.1))
        XCTAssertEqual(state.draft?.displayName, "control+a")
    }

    func testControlsAreDraftOnlyAndModifiedControlsAreChords() throws {
        let existing = try ShortcutParser.parse("command+a")
        var state = TriggerRecognizer(existingTrigger: existing)
        XCTAssertEqual(state.draft, existing)
        XCTAssertEqual(down(&state, 53), .cancel)
        XCTAssertEqual(state.draft, existing)
        XCTAssertEqual(down(&state, 36), .commit)
        XCTAssertEqual(down(&state, 76), .commit)
        XCTAssertEqual(down(&state, 51), .clear)
        XCTAssertNil(state.draft)
        XCTAssertNil(down(&state, 117))
        for code in [53, 36, 76, 51, 117, 49] {
            let expected = KeyTrigger(kind: .keyPress, keyCode: code, keyName: "raw", modifiers: [.command])
            XCTAssertEqual(state.keyDown(keyCode: code, keyName: "raw", modifiers: [.command, .fn, .capsLock], timestamp: 0), .chord(expected))
            XCTAssertEqual(state.draft, expected)
        }
        XCTAssertEqual(down(&state, 117), .clear)
        XCTAssertNil(down(&state, 49))
    }

    func testLatchingNoiseDoesNotBlockTapOrControlsOrBecomeChordModifiers() throws {
        let noise: Set<Modifier> = [.capsLock, .fn]
        var state = TriggerRecognizer(existingTrigger: try ShortcutParser.parse("command+a"))
        for (code, intent) in [(53, TriggerRecognizer.Intent.cancel), (36, .commit), (76, .commit), (51, .clear)] {
            XCTAssertEqual(state.keyDown(keyCode: code, keyName: "control", modifiers: noise, timestamp: 0), intent)
            _ = state.keyUp(keyCode: code, keyName: "control", modifiers: noise, timestamp: 0)
        }
        XCTAssertNil(state.flagsChanged(keyCode: 59, modifiers: noise.union([.control]), timestamp: 1))
        XCTAssertEqual(state.flagsChanged(keyCode: 59, modifiers: noise, timestamp: 1.01), .tap("left-control"))
        XCTAssertNil(state.keyDown(keyCode: 59, keyName: "left-control", modifiers: noise.union([.control]), timestamp: 1.1))
        XCTAssertEqual(state.keyUp(keyCode: 59, keyName: "left-control", modifiers: noise, timestamp: 1.11), .doubleTap("left-control"))
        let previousDraft = state.draft
        XCTAssertNil(state.keyDown(keyCode: 123, keyName: "left", modifiers: noise, timestamp: 2))
        XCTAssertEqual(state.draft, previousDraft)
        let arrow = KeyTrigger(kind: .keyPress, keyCode: 123, keyName: "left", modifiers: [.command])
        XCTAssertEqual(state.keyDown(keyCode: 123, keyName: "left", modifiers: noise.union([.command]), timestamp: 2.1), .chord(arrow))
        XCTAssertEqual(state.draft, arrow)
        XCTAssertEqual(state.keyDown(keyCode: 117, keyName: "delete", modifiers: noise, timestamp: 3), .clear)
        XCTAssertNil(state.draft)
    }

    func testUnmodifiedOrdinaryKeyDoesNotReplaceDraft() throws {
        let existing = try ShortcutParser.parse("command+a")
        var state = TriggerRecognizer(existingTrigger: existing)
        for modifiers: Set<Modifier> in [[], [.capsLock, .fn]] {
            XCTAssertNil(state.keyDown(keyCode: 0, keyName: "a", modifiers: modifiers, timestamp: 0))
            XCTAssertEqual(state.draft, existing)
            _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: modifiers, timestamp: 0.1)
        }
        var empty = TriggerRecognizer()
        XCTAssertNil(down(&empty, 0))
        XCTAssertNil(empty.draft)
    }

    func testDoubleTapUsesSharedWindowBoundary() throws {
        let trigger = try ShortcutParser.parse("left-option")
        for delta in [OneShotModifierState.doubleTapWindow, OneShotModifierState.doubleTapWindow + 0.001] {
            var state = TriggerRecognizer()
            _ = state.keyDown(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: 0)
            _ = state.keyUp(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: 0)
            _ = state.keyDown(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: delta)
            let result = state.keyUp(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: delta)
            XCTAssertEqual(result, delta == OneShotModifierState.doubleTapWindow
                           ? .doubleTap(trigger.keyName) : .tap(trigger.keyName))
        }
    }

    func testChordBetweenTapsBreaksDoubleTapSequence() throws {
        let trigger = try ShortcutParser.parse("left-control")
        var state = TriggerRecognizer()
        _ = tap(&state, trigger, at: 0)
        _ = state.keyDown(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0.02)
        _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0.03)
        XCTAssertEqual(tap(&state, trigger, at: 0.04), .tap(trigger.keyName))
    }

    func testInitiallyHeldOrdinaryKeyPreventsModifierTapUntilRelease() throws {
        let trigger = try ShortcutParser.parse("left-shift")
        let existing = try ShortcutParser.parse("command+a")
        var state = TriggerRecognizer(existingTrigger: existing, heldKeyCodes: [0])
        XCTAssertNil(tap(&state, trigger, at: 0.1))
        XCTAssertEqual(state.draft, existing)
        _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0.2)
        XCTAssertEqual(tap(&state, trigger, at: 0.3), .tap(trigger.keyName))

        let control = try ShortcutParser.parse("left-control")
        var mixed = TriggerRecognizer(heldModifierKeyCodes: [control.keyCode], heldKeyCodes: [0, trigger.keyCode])
        XCTAssertEqual(mixed.pressedModifierKeyCodes, [control.keyCode, trigger.keyCode])
        XCTAssertNil(mixed.keyUp(keyCode: control.keyCode, keyName: control.keyName, modifiers: [.shift], timestamp: 0))
        XCTAssertNil(mixed.keyUp(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: 0.1))
        _ = mixed.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0.2)
        XCTAssertEqual(tap(&mixed, trigger, at: 0.3), .tap(trigger.keyName))
    }

    func testReconcileInitiallyHeldKeysRepairsMissingReleaseOnly() throws {
        let trigger = try ShortcutParser.parse("left-shift")
        var state = TriggerRecognizer(heldKeyCodes: [0])
        state.reconcileInitiallyHeldKeys(stillPressed: [0])
        XCTAssertNil(tap(&state, trigger, at: 0))
        // The startup key-up was swallowed before the recorder received it.
        state.reconcileInitiallyHeldKeys(stillPressed: [])
        XCTAssertEqual(tap(&state, trigger, at: 1), .tap(trigger.keyName))

        // A later press of that same key is no longer owned by reconciliation.
        _ = state.keyDown(keyCode: 0, keyName: "a", modifiers: [], timestamp: 2)
        state.reconcileInitiallyHeldKeys(stillPressed: [])
        XCTAssertNil(tap(&state, trigger, at: 2.1))
        _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 2.2)
        XCTAssertEqual(tap(&state, trigger, at: 3), .tap(trigger.keyName))

        // Nor may a snapshot remove an unrelated key pressed after startup.
        _ = state.keyDown(keyCode: 1, keyName: "s", modifiers: [], timestamp: 4)
        state.reconcileInitiallyHeldKeys(stillPressed: [])
        XCTAssertNil(tap(&state, trigger, at: 4.1))
    }

    func testStartupReleaseThenRepressIsNotRemovedByReconciliation() throws {
        let trigger = try ShortcutParser.parse("left-shift")
        var state = TriggerRecognizer(heldKeyCodes: [0])
        _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0)
        _ = state.keyDown(keyCode: 0, keyName: "a", modifiers: [], timestamp: 1)
        state.reconcileInitiallyHeldKeys(stillPressed: [])
        XCTAssertNil(tap(&state, trigger, at: 1.1))
    }

    func testModifierPressedWhileOrdinaryKeyHeldCannotTap() throws {
        var state = TriggerRecognizer()
        let trigger = try ShortcutParser.parse("left-shift")
        _ = down(&state, 0)
        XCTAssertNil(tap(&state, trigger, at: 0.1))
        _ = state.keyUp(keyCode: 0, keyName: "a", modifiers: [], timestamp: 0.2)
        XCTAssertEqual(tap(&state, trigger, at: 0.3), .tap(trigger.keyName))
    }

    func testUnknownFlagsAndUnmatchedReleaseDoNotCapture() {
        var state = TriggerRecognizer()
        XCTAssertNil(state.flagsChanged(keyCode: 57, modifiers: [.capsLock], timestamp: 0))
        XCTAssertNil(state.keyUp(keyCode: 59, keyName: "left-control", modifiers: [], timestamp: 1))
        XCTAssertNil(state.draft)
    }

    private func down(_ state: inout TriggerRecognizer, _ code: Int) -> TriggerRecognizer.Intent? {
        state.keyDown(keyCode: code, keyName: "raw", modifiers: [], timestamp: 0)
    }

    private func tap(_ state: inout TriggerRecognizer, _ trigger: KeyTrigger, at time: Double) -> TriggerRecognizer.Intent? {
        _ = state.keyDown(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: time)
        return state.keyUp(keyCode: trigger.keyCode, keyName: trigger.keyName, modifiers: [], timestamp: time + 0.01)
    }
}
