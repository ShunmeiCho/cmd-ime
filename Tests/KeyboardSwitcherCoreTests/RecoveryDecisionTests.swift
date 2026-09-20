import XCTest
@testable import KeyboardSwitcherCore

final class RecoveryDecisionTests: XCTestCase {
    /// A context that would be recovered, so each test can spoil exactly one thing about it.
    private func context(
        isSecureEventInput: Bool = false,
        bundleID: String = "com.apple.TextEdit",
        axRole: String = "AXTextArea",
        axSubrole: String? = nil,
        isEditable: Bool = true,
        hasSelection: Bool = false,
        hasMarkedText: Bool? = false,
        textBeforeCaret: String = "nihao",
        targetSourceID: String? = "com.tencent.inputmethod.wetype.pinyin"
    ) -> RecoveryContext {
        RecoveryContext(
            isSecureEventInput: isSecureEventInput,
            bundleID: bundleID,
            axRole: axRole,
            axSubrole: axSubrole,
            isEditable: isEditable,
            hasSelection: hasSelection,
            hasMarkedText: hasMarkedText,
            textBeforeCaret: textBeforeCaret,
            targetSourceID: targetSourceID
        )
    }

    func testRecoversTheRunBeforeTheCaret() {
        XCTAssertEqual(RecoveryPolicy.decide(context(textBeforeCaret: "你好nihao")), .recover(run: "nihao"))
    }

    /// Any process can turn this on, so it is a refusal for every editor, even a verified one.
    func testRefusesWhileSecureEventInputIsOn() {
        XCTAssertEqual(RecoveryPolicy.decide(context(isSecureEventInput: true)), .refuse(.secureEventInput))
    }

    func testRefusesInAPasswordField() {
        XCTAssertEqual(
            RecoveryPolicy.decide(context(axSubrole: "AXSecureTextField")),
            .refuse(.passwordField)
        )
    }

    func testRefusesInAnEditorRecoveryHasNotBeenMeasuredIn() {
        XCTAssertEqual(
            RecoveryPolicy.decide(context(bundleID: "com.apple.Safari", axRole: "AXTextArea")),
            .refuse(.unverifiedEditor(bundleID: "com.apple.Safari", role: "AXTextArea"))
        )
        // Same app, a control whose undo behaviour was never measured.
        XCTAssertEqual(
            RecoveryPolicy.decide(context(axRole: "AXTextField")),
            .refuse(.unverifiedEditor(bundleID: "com.apple.TextEdit", role: "AXTextField"))
        )
    }

    func testRefusesWithAnInputSourceRecoveryHasNotBeenMeasuredWith() {
        XCTAssertEqual(
            RecoveryPolicy.decide(context(targetSourceID: "im.rime.inputmethod.Squirrel.Hans")),
            .refuse(.unverifiedInputSource(id: "im.rime.inputmethod.Squirrel.Hans"))
        )
        XCTAssertEqual(RecoveryPolicy.decide(context(targetSourceID: nil)), .refuse(.noChineseSource))
    }

    /// Recovery is defined against the caret. A selection means the user meant something else.
    func testRefusesWhenTextIsSelected() {
        XCTAssertEqual(RecoveryPolicy.decide(context(hasSelection: true)), .refuse(.textSelected))
    }

    func testRefusesWhenTheEditorIsAlreadyComposingOrWillNotSay() {
        XCTAssertEqual(RecoveryPolicy.decide(context(hasMarkedText: true)), .refuse(.alreadyComposing))
        XCTAssertEqual(RecoveryPolicy.decide(context(hasMarkedText: nil)), .refuse(.compositionStateUnknown))
    }

    func testRefusesWhenThereIsNothingToTake() {
        XCTAssertEqual(RecoveryPolicy.decide(context(textBeforeCaret: "你好")), .refuse(.nothingBeforeCaret))
        XCTAssertEqual(RecoveryPolicy.decide(context(textBeforeCaret: "nihao ")), .refuse(.nothingBeforeCaret))
    }

    func testRefusesWhatDoesNotReadAsPinyin() {
        XCTAssertEqual(
            RecoveryPolicy.decide(context(textBeforeCaret: "Hello world")),
            .refuse(.notPinyin(run: "Hello world"))
        )
    }

    /// Every refusal has to be explainable to the user; a silent one reads as a broken feature.
    func testEveryRefusalSaysSomething() {
        let refusals: [RecoveryRefusal] = [
            .secureEventInput, .passwordField, .notEditable,
            .unverifiedEditor(bundleID: "a", role: "b"), .noChineseSource,
            .unverifiedInputSource(id: "c"), .textSelected, .alreadyComposing,
            .compositionStateUnknown, .nothingBeforeCaret, .notPinyin(run: "d"),
        ]
        for refusal in refusals {
            XCTAssertFalse(refusal.message.isEmpty, "\(refusal) has no message")
        }
    }
}
