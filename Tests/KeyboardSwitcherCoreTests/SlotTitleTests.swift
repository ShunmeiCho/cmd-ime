import XCTest
@testable import KeyboardSwitcherCore

final class SlotTitleTests: XCTestCase {
    private func titles(_ fixture: IndicatorSlotFixture) -> [String] {
        let titles = SlotTitleResolver.titles(for: fixture.slots, sources: fixture.sources)
        return fixture.slots.map { titles[$0.id] ?? "missing" }
    }

    func testAutomaticNamesBecomeCapitalisedEndonyms() {
        XCTAssertEqual(
            titles(.languages(["de", "fr", "ru", "ar"])),
            ["Deutsch", "Français", "Русский", "العربية"]
        )
    }

    func testRenamedSlotKeepsItsName() {
        let fixture = IndicatorSlotFixture([("de", "German", "Work"), ("fr", "French - PC", "french - pc")])
        XCTAssertEqual(titles(fixture), ["Work", "Français"])
    }

    func testMissingEndonymOrSourceFallsBackToTheSlotName() {
        XCTAssertEqual(titles(IndicatorSlotFixture([("xx", "Foo", nil)])), ["Foo"])
        let slot = SwitchSlot.legacyDefaults[0]
        XCTAssertEqual(SlotTitleResolver.title(slot: slot, source: nil), "English")
    }

    func testSharedTitlesUseTheFullLanguageTag() {
        XCTAssertEqual(titles(.languages(["zh-Hans", "zh-Hant"])), ["简体中文", "繁體中文"])
        // Two sources of one language cannot be told apart by name; the detail line does that.
        XCTAssertEqual(titles(.languages(["ja", "ja"])), ["日本語", "日本語"])
    }

    func testDirectionFollowsTheTargetLanguage() {
        for language in ["ar", "fa", "he"] {
            XCTAssertTrue(SlotTitleResolver.isRightToLeft(language: language), language)
        }
        for language in ["en", "ru", "zh-Hans", "xx", ""] {
            XCTAssertFalse(SlotTitleResolver.isRightToLeft(language: language), language)
        }
        XCTAssertFalse(SlotTitleResolver.isRightToLeft(language: nil))
    }
}
