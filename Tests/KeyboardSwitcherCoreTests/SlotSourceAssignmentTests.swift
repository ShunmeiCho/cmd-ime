import XCTest
@testable import KeyboardSwitcherCore

final class SlotSourceAssignmentTests: XCTestCase {
    private let sources = [
        InputSourceInfo(id: "en.one", localizedName: "English", languages: ["en"], isSelectCapable: true),
        InputSourceInfo(id: "zh.one", localizedName: "Chinese", languages: ["zh"], isSelectCapable: true),
        InputSourceInfo(id: "ja.one", localizedName: "Japanese", languages: ["ja"], isSelectCapable: true),
    ]

    private func pinned() -> SwitcherConfig {
        var config = SwitcherConfig.default
        for (role, source) in zip(InputRole.legacy, sources) {
            config.pinInputSourceID(source.id, for: role)
        }
        return config
    }

    func testThreePinnedSlotsAllPermutationsPreserveIdentityTriggersAndLegacyRules() throws {
        let original = pinned()
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for permutation in permutations {
            var config = original
            for index in 0..<3 {
                config = try config.selectingInputSource(sources[permutation[index]], for: InputRole.legacy[index], sources: sources)
            }
            XCTAssertEqual(config.slots, original.slots)
            XCTAssertEqual(config.bindings, original.bindings)
            XCTAssertEqual(config.switchIndicatorCustomRoleColorHexes, original.switchIndicatorCustomRoleColorHexes)
            for index in 0..<3 {
                let role = InputRole.legacy[index]
                let preference = config.preference(for: role)
                XCTAssertEqual(preference.preferredIDs.first, sources[permutation[index]].id)
                XCTAssertEqual(InputSourceMatcher.bestMatch(for: role, sources: sources, config: config)?.id, sources[permutation[index]].id)
                XCTAssertEqual(preference.languagePrefixes, original.preference(for: role).languagePrefixes)
                XCTAssertEqual(preference.nameContains, original.preference(for: role).nameContains)
                XCTAssertTrue(Set(original.preference(for: role).preferredIDs).isSubset(of: Set(preference.preferredIDs)))
                XCTAssertNil(preference.fallbackLanguage)
            }
        }
        XCTAssertEqual(original, pinned())
    }

    func testTwoSourcesThreeSlotsDisableOwnedChoicesOnlyForUnmatchedSlot() throws {
        let config = pinned()
        let available = Array(sources.prefix(2))
        XCTAssertNil(InputSourceMatcher.bestMatch(for: .japanese, sources: available, config: config))
        for (index, source) in available.enumerated() {
            let policy = config.inputSourceSelection(source, for: .japanese, sources: available)
            XCTAssertEqual(policy, .usedBy(InputRole.legacy[index]))
            XCTAssertFalse(policy.isEnabled)
            XCTAssertThrowsError(try config.selectingInputSource(source, for: .japanese, sources: available))
        }
        XCTAssertEqual(config.inputSourceSelection(sources[1], for: .english, sources: available), .swap(with: .chinese))
        let swapped = try config.selectingInputSource(sources[1], for: .english, sources: available)
        XCTAssertEqual(swapped.preference(for: .english).preferredIDs.first, sources[1].id)
        XCTAssertEqual(swapped.preference(for: .chinese).preferredIDs.first, sources[0].id)
        XCTAssertEqual(swapped.preference(for: .japanese), config.preference(for: .japanese))
    }

    func testDynamicFallbackLanguageFollowsIncomingSource() throws {
        let config = SwitcherConfig.detected(from: sources)
        let swapped = try config.swappingInputSources(between: .english, and: .japanese, sources: sources)
        XCTAssertEqual(swapped.preference(for: .english).fallbackLanguage, "ja")
        XCTAssertEqual(swapped.preference(for: .japanese).fallbackLanguage, "en")
        XCTAssertEqual(swapped.slots, config.slots)
        XCTAssertEqual(swapped.bindings, config.bindings)
        let fallbacks = sources.map { InputSourceInfo(id: $0.id + ".fallback", localizedName: $0.localizedName, languages: $0.languages, isSelectCapable: true) }
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .english, sources: fallbacks, config: swapped)?.id, "ja.one.fallback")
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .japanese, sources: fallbacks, config: swapped)?.id, "en.one.fallback")
    }

    func testMissingPreferredIDTransfersAndRestoresInsteadOfPinningFallback() throws {
        let config = SwitcherConfig.detected(from: sources)
        let fallback = InputSourceInfo(id: "en.fallback", localizedName: "Fallback", languages: ["en"], isSelectCapable: true)
        let available = [fallback, sources[1], sources[2]]
        XCTAssertEqual(config.inputSourceSelection(sources[1], for: .english, sources: available), .swap(with: .chinese))
        let swapped = try config.selectingInputSource(sources[1], for: .english, sources: available)
        XCTAssertEqual(swapped.preference(for: .chinese).preferredIDs, ["en.one"])
        XCTAssertEqual(swapped.preference(for: .chinese).fallbackLanguage, "en")
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .chinese, sources: available, config: swapped)?.id, fallback.id)
        XCTAssertEqual(InputSourceMatcher.bestMatch(for: .chinese, sources: available + [sources[0]], config: swapped)?.id, "en.one")
    }

    func testThirdOwnerCollisionsRejectBothIncomingAndOutgoingIDs() throws {
        for duplicate in [sources[0], sources[1]] {
            var config = pinned()
            config.pinInputSourceID(duplicate.id, for: .japanese)
            XCTAssertThrowsError(try config.swappingInputSources(between: .english, and: .chinese, sources: sources)) { error in
                XCTAssertEqual(error as? SlotError, .sourceAlreadyUsed)
            }
            XCTAssertFalse(config.inputSourceSelection(sources[1], for: .english, sources: sources).isEnabled)
            XCTAssertThrowsError(try config.selectingInputSource(sources[1], for: .english, sources: sources))
        }
    }

    func testSameSlotUnknownUnmatchedAndUnownedSelection() throws {
        let config = pinned()
        XCTAssertEqual(try config.swappingInputSources(between: .english, and: .english, sources: []), config)
        XCTAssertEqual(try config.selectingInputSource(sources[0], for: .english, sources: sources), config)
        XCTAssertThrowsError(try config.swappingInputSources(between: .english, and: InputRole(rawValue: "unknown"), sources: sources))
        XCTAssertThrowsError(try config.swappingInputSources(between: .english, and: .chinese, sources: []))
        let unowned = InputSourceInfo(id: "ko.one", localizedName: "Korean", languages: ["ko"], isSelectCapable: true)
        XCTAssertEqual(config.inputSourceSelection(unowned, for: .japanese, sources: [unowned]), .assign)
        XCTAssertEqual(try config.selectingInputSource(unowned, for: .japanese, sources: [unowned]), try config.assigningInputSource(unowned, to: .japanese))
        XCTAssertEqual(config.inputSourceSelection(unowned, for: .english, sources: []), .unavailable)
    }

    func testRuleOnlySlotUsesResolvedSourceWithoutMovingRules() throws {
        var config = pinned()
        config.inputSources[InputRole.english.rawValue] = RoleInputSourcePreference(languagePrefixes: ["en"], nameContains: ["English"])
        let swapped = try config.selectingInputSource(sources[1], for: .english, sources: sources)
        XCTAssertEqual(swapped.preference(for: .chinese).preferredIDs.first, "en.one")
        XCTAssertEqual(swapped.preference(for: .english).preferredIDs, ["zh.one"])
        XCTAssertEqual(swapped.preference(for: .english).languagePrefixes, ["en"])
        XCTAssertEqual(swapped.preference(for: .english).nameContains, ["English"])
    }
}
