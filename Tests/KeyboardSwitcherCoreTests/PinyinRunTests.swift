import XCTest
@testable import KeyboardSwitcherCore

final class PinyinRunTests: XCTestCase {
    func testTakesTheLettersImmediatelyBeforeTheCaret() {
        XCTAssertEqual(PinyinRun.candidate(before: "nihao").map(String.init), "nihao")
        XCTAssertEqual(PinyinRun.candidate(before: "Hello nihao").map(String.init), "Hello nihao")
    }

    /// Existing Chinese ends the run: whatever is behind it was already recovered or typed.
    func testStopsAtNonLatinText() {
        XCTAssertEqual(PinyinRun.candidate(before: "你好nihao").map(String.init), "nihao")
        XCTAssertEqual(PinyinRun.candidate(before: "ありがとうnihao").map(String.init), "nihao")
    }

    func testStopsAtPunctuationAndNewlines() {
        XCTAssertEqual(PinyinRun.candidate(before: "hi, nihao").map(String.init), "nihao")
        XCTAssertEqual(PinyinRun.candidate(before: "one.two").map(String.init), "two")
        XCTAssertEqual(PinyinRun.candidate(before: "first\nnihao").map(String.init), "nihao")
        XCTAssertEqual(PinyinRun.candidate(before: "a1nihao").map(String.init), "nihao")
    }

    func testDoubleSpaceAndTrailingSpaceEndTheRun() {
        XCTAssertEqual(PinyinRun.candidate(before: "ni  hao").map(String.init), "hao")
        XCTAssertNil(PinyinRun.candidate(before: "nihao "))
        XCTAssertNil(PinyinRun.candidate(before: ""))
        XCTAssertNil(PinyinRun.candidate(before: "、"))
    }

    func testPlausiblePinyinIsAccepted() {
        for run in ["nihao", "zhongguo", "xian", "ni hao", "a", "me", "shuangpin", "nv", "lve"] {
            XCTAssertTrue(PinyinRun.isPlausible(run), "\(run) should read as pinyin")
        }
    }

    func testTextThatIsNotPinyinIsRefused() {
        for run in ["hello", "qz", "xyz", "thanks", ""] {
            XCTAssertFalse(PinyinRun.isPlausible(run), "\(run) should not read as pinyin")
        }
    }

    /// An ambiguous run is still accepted: which reading is meant is the input method's job,
    /// and the user's, not ours.
    func testAmbiguityDoesNotReject() {
        XCTAssertTrue(PinyinRun.isPlausible("xian"))
        XCTAssertTrue(PinyinRun.isPlausible("nixian"))
    }
}
