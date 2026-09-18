import XCTest
@testable import KeyboardSwitcherCore

final class SlotMatchExplanationTests: XCTestCase {
    private let role = InputRole(rawValue: "custom-slot")
    private let first = InputSourceInfo(
        id: "first", localizedName: "First", languages: ["en"], isSelectCapable: true
    )
    private let second = InputSourceInfo(
        id: "second", localizedName: "Alternative", languages: ["ja"], isSelectCapable: true
    )

    private func config(_ preference: RoleInputSourcePreference) -> SwitcherConfig {
        SwitcherConfig(bindings: [], inputSources: [role.rawValue: preference])
    }

    private func assertExplanation(
        _ expected: SlotMatchExplanation,
        tier: InputSourceMatchTier,
        sources: [InputSourceInfo],
        preference: RoleInputSourcePreference,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let configuration = config(preference)
        XCTAssertEqual(
            InputSourceMatcher.match(for: role, sources: sources, config: configuration).tier,
            tier, file: file, line: line
        )
        XCTAssertEqual(
            SlotMatchExplanation.resolve(for: role, sources: sources, config: configuration),
            expected, file: file, line: line
        )
    }

    func testFirstPreferredIsPinnedRegardlessOfScanOrderAndOtherRules() {
        assertExplanation(
            .pinned, tier: .preferredID, sources: [second, first],
            preference: RoleInputSourcePreference(
                preferredIDs: [first.id, second.id], languagePrefixes: ["ja"],
                nameContains: ["Alternative"], fallbackLanguage: "ja"
            )
        )
    }

    func testSecondaryPreferredExplainsUnavailableFirstPreference() {
        assertExplanation(
            .unavailablePreferred(preferredID: first.id, using: second),
            tier: .preferredID, sources: [second],
            preference: RoleInputSourcePreference(preferredIDs: [first.id, second.id])
        )
    }

    func testUnselectableFirstPreferenceIsUnavailable() {
        var unavailable = first
        unavailable.isSelectCapable = false
        assertExplanation(
            .unavailablePreferred(preferredID: first.id, using: second),
            tier: .preferredID, sources: [unavailable, second],
            preference: RoleInputSourcePreference(preferredIDs: [first.id, second.id])
        )
    }

    func testAuxiliaryPreferredSourceIsNotPinned() {
        let auxiliary = InputSourceInfo(
            id: "palette", localizedName: "Palette", languages: ["ja"], isSelectCapable: true
        )
        assertExplanation(
            .unavailablePreferred(preferredID: auxiliary.id, using: second),
            tier: .fallbackLanguage, sources: [auxiliary, second],
            preference: RoleInputSourcePreference(preferredIDs: [auxiliary.id], fallbackLanguage: "ja")
        )
    }

    func testEveryAutomaticTierWithAndWithoutUnavailablePreference() {
        let rules: [(InputSourceMatchTier, RoleInputSourcePreference)] = [
            (.fallbackLanguage, RoleInputSourcePreference(fallbackLanguage: "ja")),
            (.languagePrefix, RoleInputSourcePreference(languagePrefixes: ["JA"])),
            (.nameContains, RoleInputSourcePreference(nameContains: ["ALTERNATIVE"])),
        ]
        for (tier, preference) in rules {
            assertExplanation(
                .automatic(source: second), tier: tier, sources: [second], preference: preference
            )
            var pinnedPreference = preference
            pinnedPreference.preferredIDs = [first.id]
            assertExplanation(
                .unavailablePreferred(preferredID: first.id, using: second),
                tier: tier, sources: [second], preference: pinnedPreference
            )
        }
    }

    func testFallbackLanguageWinsOverLegacyLanguageAndNameRules() {
        assertExplanation(
            .automatic(source: second), tier: .fallbackLanguage, sources: [first, second],
            preference: RoleInputSourcePreference(
                languagePrefixes: ["en"], nameContains: ["First"], fallbackLanguage: "ja"
            )
        )
    }

    func testLegacyLanguageRulesKeepSourceFirstTieBreaking() {
        assertExplanation(
            .automatic(source: first), tier: .languagePrefix, sources: [first, second],
            preference: RoleInputSourcePreference(languagePrefixes: ["ja", "en"])
        )
    }

    func testNoMatchWithOrWithoutPreferredID() {
        for preferredIDs in [[], [first.id]] {
            let preference = RoleInputSourcePreference(preferredIDs: preferredIDs)
            assertExplanation(.unmatched, tier: .none, sources: [], preference: preference)
            assertExplanation(.unmatched, tier: .none, sources: [second], preference: preference)
        }
    }

    func testMissingRolePreferenceDoesNotInferLanguage() {
        XCTAssertEqual(
            SlotMatchExplanation.resolve(for: role, sources: [first], config: .default),
            .unmatched
        )
    }

    func testLegacyDefaultSecondaryIDIsNotReportedAsPinned() {
        let us = InputSourceInfo(
            id: "com.apple.keylayout.US", localizedName: "U.S.",
            languages: ["en"], isSelectCapable: true
        )
        XCTAssertEqual(
            SlotMatchExplanation.resolve(for: .english, sources: [us], config: .default),
            .unavailablePreferred(preferredID: "com.apple.keylayout.ABC", using: us)
        )
    }
}
