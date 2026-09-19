import XCTest
@testable import KeyboardSwitcherCore

final class SwitchActivationPolicyTests: XCTestCase {
    private func source(_ id: String, _ language: String) -> InputSourceInfo {
        InputSourceInfo(id: id, localizedName: id, languages: [language], isSelectCapable: true)
    }

    func testKanaPreludeAppliesOnlyWhenEnteringAJapaneseInputMethodFromAnotherLanguage() {
        let abc = source("com.apple.keylayout.ABC", "en")
        let google = source("com.google.inputmethod.Japanese.base", "ja")
        let azooKey = source("dev.ensan.inputmethod.azooKeyMac.Japanese", "ja")
        let pinyin = source("com.tencent.inputmethod.wetype.pinyin", "zh-Hans")

        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: google, current: abc))
        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: azooKey, current: pinyin))
        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: google, current: nil))
        // Inside Japanese the system passes Kana to the app instead of switching.
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: google, current: azooKey))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: pinyin, current: abc))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: abc, current: google))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: source("com.apple.keylayout.Japanese", "ja"), current: abc))
    }
}
