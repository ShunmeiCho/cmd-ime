import XCTest
@testable import KeyboardSwitcherCore

final class LabLatinModeTests: XCTestCase {
    func testPicksTheLatinModeKeyByTheTextTheSourceProduces() {
        XCTAssertEqual(LabLatinMode.forSource(id: "dev.ensan.inputmethod.azooKeyMac.Japanese"), .japanese)
        XCTAssertEqual(LabLatinMode.forSource(id: "com.tencent.inputmethod.wetype.pinyin"), .pinyin)
        XCTAssertEqual(LabLatinMode.forSource(id: "com.bytedance.inputmethod.doubaoime.pinyin"), .pinyin)
        XCTAssertNil(LabLatinMode.forSource(id: "com.apple.keylayout.ABC"))
        XCTAssertNil(LabLatinMode.forSource(id: "com.apple.inputmethod.Korean.2SetKorean"))
        XCTAssertNil(LabLatinMode.forSource(id: "com.example.unknown"))
    }

    func testHoldsOnlyWhenTheProbeStayedLatin() {
        XCTAssertTrue(LabLatinMode.holds(probeText: "a "))
        XCTAssertTrue(LabLatinMode.holds(probeText: "a\n"))
        XCTAssertFalse(LabLatinMode.holds(probeText: "あ"))
        XCTAssertFalse(LabLatinMode.holds(probeText: "啊"))
        XCTAssertFalse(LabLatinMode.holds(probeText: "aあ"))
        XCTAssertFalse(LabLatinMode.holds(probeText: ""))
    }

    func testDoubaoIsJudgedAsPinyin() {
        XCTAssertEqual(LabExpectation.forSource(id: "com.bytedance.inputmethod.doubaoime.pinyin"), .pinyin)
    }
}
