import XCTest
@testable import KeyboardSwitcherCore

final class SwitchActivationPolicyTests: XCTestCase {
    private func source(_ id: String, _ language: String) -> InputSourceInfo {
        InputSourceInfo(id: id, localizedName: id, languages: [language], isSelectCapable: true)
    }

    func testKanaPreludeAppliesOnlyWhenEnteringAListedInputMethodFromAnotherLanguage() {
        let abc = source("com.apple.keylayout.ABC", "en")
        let google = source("com.google.inputmethod.Japanese.base", "ja")
        let azooKey = source("dev.ensan.inputmethod.azooKeyMac.Japanese", "ja")
        let pinyin = source("com.tencent.inputmethod.wetype.pinyin", "zh-Hans")

        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: google, current: abc))
        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: google, current: pinyin))
        // Not listed: a plain select already works for it.
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: azooKey, current: abc))
        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: google, current: nil))
        // Inside Japanese the system passes Kana to the app instead of switching.
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: google, current: azooKey))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: pinyin, current: abc))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: abc, current: google))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: source("com.apple.keylayout.Japanese", "ja"), current: abc))
    }

    func testUserRecipesAddInputMethodsAndCanSwitchOffABuiltInOne() {
        let google = source("com.google.inputmethod.Japanese.base", "ja")
        let other = source("com.example.inputmethod.Japanese", "ja")
        let pinyin = source("com.tencent.inputmethod.wetype.pinyin", "zh-Hans")
        let recipes = [
            ActivationRecipe(sourceIDPrefix: "com.example.inputmethod", strategy: .kanaThenSelect, delayMs: 9000),
            ActivationRecipe(sourceIDPrefix: "com.google.inputmethod.Japanese", strategy: .select),
            ActivationRecipe(sourceIDPrefix: "com.tencent", strategy: .kanaThenSelect),
        ]

        XCTAssertTrue(SwitchActivationPolicy.needsKanaPrelude(target: other, current: nil, userRecipes: recipes))
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: google, current: nil, userRecipes: recipes))
        // Kana cannot enter a Chinese source, whatever a recipe says.
        XCTAssertFalse(SwitchActivationPolicy.needsKanaPrelude(target: pinyin, current: nil, userRecipes: recipes))
        XCTAssertEqual(SwitchActivationPolicy.kanaToSelectDelay(for: other, userRecipes: recipes), 0.5, "delays are clamped")
        XCTAssertEqual(SwitchActivationPolicy.kanaToSelectDelay(for: google), SwitchActivationPolicy.kanaToSelectDelay)
    }

    func testRecipeStoreKeepsGoodEntriesAndReportsBadOnes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recipes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ActivationRecipeStore(url: url).load(), .init(recipes: [], problems: []), "no file is the normal case")

        try Data("""
        {"recipes": [
          {"sourceIDPrefix": "com.example.inputmethod", "strategy": "kanaThenSelect", "delayMs": 80},
          {"sourceIDPrefix": "com.example.other", "strategy": "teleport"},
          {"sourceIDPrefix": " ", "strategy": "select"},
          "nonsense"
        ]}
        """.utf8).write(to: url)
        let result = ActivationRecipeStore(url: url).load()
        XCTAssertEqual(result.recipes, [ActivationRecipe(sourceIDPrefix: "com.example.inputmethod", strategy: .kanaThenSelect, delayMs: 80)])
        XCTAssertEqual(result.problems.count, 3)

        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(ActivationRecipeStore(url: url).load().recipes, [])
        XCTAssertEqual(ActivationRecipeStore(url: url).load().problems.count, 1)
    }
}
