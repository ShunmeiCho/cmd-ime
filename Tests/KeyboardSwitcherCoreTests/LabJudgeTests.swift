import XCTest
@testable import KeyboardSwitcherCore

final class LabJudgeTests: XCTestCase {
    private func observation(
        text: String,
        baseline: String = "n",
        before: String = "",
        reported: String? = "com.google.inputmethod.Japanese.base"
    ) -> LabObservation {
        LabObservation(textBefore: before, baselineText: baseline, text: text, reportedSourceID: reported)
    }

    func testTypingTheRightScriptPasses() {
        XCTAssertEqual(LabJudge.judge(observation(text: "あいう"), expectation: .japanese), .pass)
        XCTAssertEqual(LabJudge.judge(observation(text: "你好"), expectation: .pinyin), .pass)
        XCTAssertEqual(LabJudge.judge(observation(text: "nihao"), expectation: .keyboardLayout), .pass)
    }

    /// The failure the lab exists to catch: the system reports the switch and latin comes out.
    func testLatinFromAnInputMethodIsTheSilentFailure() {
        XCTAssertEqual(LabJudge.judge(observation(text: "aiu\n"), expectation: .japanese), .fail(.producedLatin))
    }

    func testWrongScriptAndNoTextAreTheirOwnFailures() {
        XCTAssertEqual(LabJudge.judge(observation(text: "あいう"), expectation: .pinyin), .fail(.producedWrongScript))
        XCTAssertEqual(LabJudge.judge(observation(text: "  \n"), expectation: .japanese), .fail(.producedNothing))
    }

    /// A reported source id never decides the verdict: it has been observed to lie.
    func testTheReportedSourceIDDoesNotChangeTheVerdict() {
        let lying = observation(text: "あいう", reported: "com.apple.keylayout.ABC")
        XCTAssertEqual(LabJudge.judge(lying, expectation: .japanese), .pass)
    }

    func testAnUntrustworthyAttemptIsVoidRatherThanAFailure() {
        if case .void = LabJudge.judge(observation(text: "あいう", baseline: ""), expectation: .japanese) {} else {
            XCTFail("a baseline that produced nothing must void the attempt")
        }
        if case .void = LabJudge.judge(observation(text: "あいう", baseline: "あ"), expectation: .japanese) {} else {
            XCTFail("a baseline that composed means the previous input method is still attached")
        }
        if case .void = LabJudge.judge(observation(text: "あいう", before: "old"), expectation: .japanese) {} else {
            XCTFail("leftover text must void the attempt")
        }
    }

    func testAnUncoveredOrUnverifiedSourceIsUnjudged() {
        if case .unjudged = LabJudge.judge(observation(text: "가"), expectation: nil) {} else {
            XCTFail("an input source with no expectation must not be judged")
        }
        if case .unjudged = LabJudge.judge(observation(text: "안녕"), expectation: .korean) {} else {
            XCTFail("an unverified expectation must not be judged")
        }
    }

    func testTheLongestMatchingPrefixWins() {
        XCTAssertEqual(LabExpectation.forSource(id: "com.apple.keylayout.ABC"), .keyboardLayout)
        XCTAssertEqual(LabExpectation.forSource(id: "com.google.inputmethod.Japanese.base"), .japanese)
        XCTAssertEqual(LabExpectation.forSource(id: "im.rime.inputmethod.Squirrel.Hans"), .pinyin)
        XCTAssertNil(LabExpectation.forSource(id: "com.sogou.inputmethod.sogou.pinyin"))
    }
}
