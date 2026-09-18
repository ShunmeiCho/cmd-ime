import XCTest
@testable import KeyboardSwitcherCore

final class SetupGuideTests: XCTestCase {
    private func source(_ language: String, id: String? = nil, selectable: Bool = true) -> InputSourceInfo {
        InputSourceInfo(id: id ?? "source.\(language)", localizedName: "Source \(id ?? language)", languages: [language], isSelectCapable: selectable)
    }

    private func evidence(for ids: [InputRole], config: SwitcherConfig, sources: [InputSourceInfo]) -> SetupTriggerEvidence {
        ids.reduce(SetupTriggerEvidence()) { evidence, id in
            guard let trigger = config.slotTriggers.first(where: { $0.slot == id })?.trigger,
                  let source = InputSourceMatcher.bestMatch(for: id, sources: sources, config: config) else { return evidence }
            return evidence.recording(SetupTriggeredSwitch(slotID: id, sourceID: source.id, trigger: trigger),
                                      config: config, sources: sources)
        }
    }

    private func temporaryStore() -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ConfigStore(url: directory.appendingPathComponent("config.json"))
    }

    private func input(
        accessibility: Bool = true,
        inputMonitoring: Bool = true,
        listenerRunning: Bool = true,
        listenerFailed: Bool = false,
        sources: Int = 2,
        slots: Int = 2,
        bound: Int = 2,
        detectable: Int? = nil,
        confirmed: Bool = false,
        completed: Bool = false
    ) -> SetupGuideInput {
        SetupGuideInput(
            accessibilityGranted: accessibility,
            inputMonitoringGranted: inputMonitoring,
            listenerRunning: listenerRunning,
            listenerFailed: listenerFailed,
            selectableSourceCount: sources,
            slotCount: slots,
            boundSlotCount: bound,
            detectableSlotCount: detectable ?? slots,
            hasConfirmedSlots: confirmed,
            hasCompletedSetup: completed
        )
    }

    // MARK: hasCompletedSetup codec

    func testConfigWithoutTheKeyDecodesAsCompleted() throws {
        let json = #"{"version":2,"showSwitchIndicator":false,"bindings":[],"inputSources":{}}"#

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.hasCompletedSetup)
        XCTAssertEqual(config.version, 2)
        XCTAssertFalse(config.showSwitchIndicator)
        XCTAssertEqual(config.slots, SwitchSlot.legacyDefaults)
    }

    func testBothValuesRoundTripThroughTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))

        for value in [false, true] {
            var config = SwitcherConfig.default
            config.hasCompletedSetup = value
            try store.save(config)

            let loaded = try store.loadOrRecover().config

            XCTAssertEqual(loaded.hasCompletedSetup, value)
            XCTAssertEqual(loaded, config)
        }
    }

    func testFreshDetectionWritesFalse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(url: directory.appendingPathComponent("config.json"))
        XCTAssertTrue(try store.loadOrRecover().isFirstRun)
        XCTAssertFalse(SwitcherConfig.default.hasCompletedSetup)

        try store.save(SwitcherConfig.detected(from: [source("en"), source("ko")]))

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        XCTAssertEqual(object?["hasCompletedSetup"] as? Bool, false)
        let reloaded = try store.loadOrRecover()
        XCTAssertFalse(reloaded.isFirstRun)
        XCTAssertFalse(reloaded.config.hasCompletedSetup)
    }

    func testCompletingSetupAndResetToDetectedKeepTheGuideHidden() {
        let pending = SwitcherConfig.detected(from: [source("en"), source("ko")])

        let completed = pending.completingSetup()

        XCTAssertFalse(pending.hasCompletedSetup)
        XCTAssertTrue(completed.hasCompletedSetup)
        var expected = pending
        expected.hasCompletedSetup = true
        XCTAssertEqual(completed, expected)
        XCTAssertTrue(completed.rebuildingSlots(from: [source("de")]).hasCompletedSetup)
    }

    func testUnreadableConfigRecoversAsCompletedAndOnlyAFirstRunIsPending() throws {
        let store = temporaryStore()
        let absent = try store.loadOrRecover()
        XCTAssertFalse(absent.config.hasCompletedSetup)
        XCTAssertTrue(absent.configForCLI.hasCompletedSetup)

        try store.save(SwitcherConfig.detected(from: [source("en"), source("ko")]))
        let pending = try store.loadOrRecover()
        XCTAssertFalse(pending.configForCLI.hasCompletedSetup)
        XCTAssertEqual(pending.configForCLI, pending.config)

        try Data("{}".utf8).write(to: store.url)
        let recovered = try store.loadOrRecover()
        XCTAssertNotNil(recovered.recoveredBackupURL)
        XCTAssertFalse(recovered.isFirstRun)
        XCTAssertTrue(recovered.config.hasCompletedSetup)
        XCTAssertEqual(recovered.configForCLI, SwitcherConfig.default.completingSetup())
    }

    func testV1FileStaysCompletedThroughLoadAndSave() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"bindings":[],"inputSources":{}}"#.utf8).write(to: store.url)

        let loaded = try store.loadOrRecover()
        try store.save(loaded.config)

        XCTAssertEqual(loaded.migratedFromVersion, 1)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        XCTAssertEqual(object?["hasCompletedSetup"] as? Bool, true)
        XCTAssertTrue(try store.loadOrRecover().config.hasCompletedSetup)
    }

    func testResetToDetectedAndRemoveUndoKeepTheStoredFlag() throws {
        let store = temporaryStore()
        let pending = SwitcherConfig.detected(from: [source("en"), source("ko")])

        for config in [pending, pending.completingSetup()] {
            let rebuilt = try store.resettingSlots(in: config, from: [source("de"), source("fr")])
            XCTAssertEqual(rebuilt.hasCompletedSetup, config.hasCompletedSetup)
            XCTAssertEqual(try store.load().hasCompletedSetup, config.hasCompletedSetup)

            let removal = try config.removingSlotWithReceipt(config.slots[0].id)
            let restored = try removal.config.restoringSlot(removal.removed).config
            XCTAssertEqual(removal.config.hasCompletedSetup, config.hasCompletedSetup)
            XCTAssertEqual(restored, config)
        }
    }

    // MARK: Step derivation

    func testCompletedSetupIsFinishedWhateverElseIsTrue() {
        let state = SetupGuideState(input(accessibility: false, inputMonitoring: false, sources: 1, completed: true))

        XCTAssertNil(state.currentStep)
        XCTAssertTrue(state.isFinished)
        XCTAssertTrue(SetupStep.allCases.allSatisfy(state.isComplete))
    }

    func testEitherMissingPermissionHoldsTheGuideAtPermissions() {
        for (accessibility, inputMonitoring) in [(false, false), (true, false), (false, true)] {
            let state = SetupGuideState(input(accessibility: accessibility, inputMonitoring: inputMonitoring, confirmed: true))

            XCTAssertEqual(state.currentStep, .permissions)
            XCTAssertFalse(state.isFinished)
            XCTAssertFalse(SetupStep.allCases.contains(where: state.isComplete))
        }
    }

    func testReadyPermissionsWaitForConfirmationThenMoveToTryIt() {
        let review = SetupGuideState(input(confirmed: false))
        let tryIt = SetupGuideState(input(confirmed: true))

        XCTAssertEqual(review.currentStep, .review)
        XCTAssertEqual(SetupStep.allCases.filter(review.isComplete), [.permissions])
        XCTAssertEqual(tryIt.currentStep, .tryIt)
        XCTAssertEqual(SetupStep.allCases.filter(tryIt.isComplete), [.permissions, .review])
        XCTAssertFalse(tryIt.isFinished)
    }

    func testFailedListenerHoldsTheGuideAtPermissionsAndOffersRelaunch() {
        let failed = SetupGuideState(input(listenerFailed: true, confirmed: true))
        let missing = SetupGuideState(input(accessibility: false, listenerFailed: true))

        XCTAssertEqual(failed.currentStep, .permissions)
        XCTAssertTrue(failed.shouldOfferRelaunch)
        XCTAssertFalse(missing.shouldOfferRelaunch)
        XCTAssertFalse(SetupGuideState(input()).shouldOfferRelaunch)
        XCTAssertNil(SetupGuideState(input(listenerFailed: true, completed: true)).currentStep)
    }

    func testPausedListenerReturnsToPermissionsDespiteConfirmedSlots() {
        let state = SetupGuideState(input(listenerRunning: false, confirmed: true))
        XCTAssertEqual(state.currentStep, .permissions)
        XCTAssertFalse(state.isComplete(.permissions))
        XCTAssertFalse(state.shouldOfferRelaunch)
    }

    func testNotStartedListenerWaitsForRunningBeforeReview() {
        var ready = input(listenerRunning: false)
        XCTAssertEqual(SetupGuideState(ready).currentStep, .permissions)
        ready.listenerRunning = true
        XCTAssertEqual(SetupGuideState(ready).currentStep, .review)
        XCTAssertTrue(SetupGuideState(ready).isComplete(.permissions))
    }

    // MARK: Edge flags

    func testNeedsMoreSourcesBelowTwoSelectableSources() {
        XCTAssertTrue(SetupGuideState(input(sources: 0)).needsMoreSources)
        XCTAssertTrue(SetupGuideState(input(sources: 1)).needsMoreSources)
        XCTAssertFalse(SetupGuideState(input(sources: 2)).needsMoreSources)
        XCTAssertEqual(SetupGuideState(input(sources: 1)).currentStep, .review)
    }

    func testUnboundSlotsReflectsTheCurrentConfigurationRatherThanTheAutomaticLimit() {
        XCTAssertTrue(SetupGuideState(input(sources: 6, slots: 6, bound: 5)).hasUnboundSlots)
        XCTAssertFalse(SetupGuideState(input(sources: 6, slots: 6, bound: 6)).hasUnboundSlots)
        XCTAssertFalse(SetupGuideState(input(sources: 5, slots: 5, bound: 5)).hasUnboundSlots)
        XCTAssertTrue(SetupGuideState(input(sources: 8, slots: 3, bound: 2)).hasUnboundSlots)
    }

    func testUnboundSlotNoticeNamesTheActuallyUnboundSlotAfterManualReassignment() {
        let sources = ["en", "de", "ru", "ko", "ja", "zh"].map { source($0) }
        var config = SwitcherConfig.detected(from: sources)
        let first = config.slots[0]
        let sixth = config.slots[5]

        config.bindings.removeAll { $0.action.role == first.id }
        config.bindings.append(KeyBinding(
            trigger: KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option]),
            action: .switchInputSource(sixth.id)
        ))

        let summary = SetupUnboundSlots(config: config)

        XCTAssertEqual(summary.names, [first.name])
        XCTAssertEqual(summary.notice, "\(first.name) has no trigger yet. Use Change to bind one. On first detection, CmdIME automatically assigns up to 5 keys.")
    }

    func testUnboundSlotNoticePromptsForAnUnboundSlotWithinTheAutomaticLimit() {
        var config = SwitcherConfig.detected(from: [source("en"), source("ko")])
        let unbound = config.slots[1]
        config.bindings.removeAll { $0.action.role == unbound.id }

        XCTAssertEqual(SetupUnboundSlots(config: config).notice, "\(unbound.name) has no trigger yet. Use Change to bind one.")
    }

    func testUnboundSlotNoticeIsAbsentWhenEverySlotIsBound() {
        let config = SwitcherConfig.detected(from: [source("en"), source("ko")])

        XCTAssertFalse(SetupUnboundSlots(config: config).hasUnboundSlots)
        XCTAssertNil(SetupUnboundSlots(config: config).notice)
    }

    func testUnboundSlotNoticeTruncatesNamesAndStatesTheTotal() {
        let slots = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"].enumerated().map { index, name in
            SwitchSlot(id: InputRole(rawValue: "slot-\(index)"), name: name, tintHex: "#4D8CFF")
        }
        let config = SwitcherConfig(slots: slots, bindings: [], inputSources: [:])

        XCTAssertEqual(
            SetupUnboundSlots(config: config).notice,
            "6 slots have no trigger yet: Alpha, Bravo, Charlie, and 3 more. Use Change to bind one. On first detection, CmdIME automatically assigns up to 5 keys."
        )
    }

    func testDetectAgainNeedsASingleSlotAndADetectionThatFindsMore() {
        XCTAssertTrue(SetupGuideState(input(sources: 2, slots: 1, bound: 1, detectable: 2)).canDetectAgain)
        // Two sources of one language: detection would rebuild the same single slot.
        XCTAssertFalse(SetupGuideState(input(sources: 2, slots: 1, bound: 1, detectable: 1)).canDetectAgain)
        XCTAssertFalse(SetupGuideState(input(sources: 3, slots: 2, bound: 2, detectable: 3)).canDetectAgain)
        XCTAssertFalse(SetupGuideState(input(sources: 0, slots: 1, bound: 1, detectable: 0)).canDetectAgain)
    }

    func testDetectableSlotCountFollowsDetectionNotTheSourceCount() {
        let sameLanguage = [source("en", id: "abc"), source("en-GB", id: "british")]
        let single = SwitcherConfig.detected(from: sameLanguage)

        let unchanged = SetupGuideInput(config: single, sources: sameLanguage, accessibilityGranted: true,
                                        inputMonitoringGranted: true, listenerRunning: true, hasConfirmedSlots: false)
        let grown = SetupGuideInput(config: single, sources: sameLanguage + [source("ko")], accessibilityGranted: true,
                                    inputMonitoringGranted: true, listenerRunning: true, hasConfirmedSlots: false)
        let nothingDetectable = SetupGuideInput(config: single, sources: [], accessibilityGranted: true,
                                                inputMonitoringGranted: true, listenerRunning: true, hasConfirmedSlots: false)

        XCTAssertEqual(unchanged.selectableSourceCount, 2)
        XCTAssertEqual(unchanged.detectableSlotCount, 1)
        XCTAssertFalse(SetupGuideState(unchanged).canDetectAgain)
        XCTAssertEqual(grown.detectableSlotCount, 2)
        XCTAssertTrue(SetupGuideState(grown).canDetectAgain)
        // Without a usable language detection falls back to the legacy slots: not a finding.
        XCTAssertEqual(nothingDetectable.detectableSlotCount, 0)
    }

    // MARK: Input from the live configuration

    func testInputCountsSelectableSourcesSlotsAndBoundSlots() throws {
        let sources = ["en", "de", "ru", "ko", "ja", "zh", "fr"].map { source($0) }
        var config = SwitcherConfig.detected(from: sources)
        let first = try XCTUnwrap(config.slots.first?.id)
        config.bindings.append(KeyBinding(
            trigger: KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option]),
            action: .switchInputSource(first)
        ))
        config.bindings.append(KeyBinding(
            trigger: KeyTrigger(kind: .keyPress, keyCode: 40, keyName: "k", modifiers: [.option]),
            action: .switchInputSource(config.slots[6].id),
            enabled: false
        ))
        config.upsertRemapBinding(
            trigger: KeyTrigger(kind: .oneShotModifier, keyCode: 57, keyName: "caps-lock"),
            output: KeyTrigger(kind: .keyPress, keyCode: 53, keyName: "escape")
        )

        let input = SetupGuideInput(
            config: config,
            sources: sources + [source("it", selectable: false)],
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            listenerRunning: true,
            hasConfirmedSlots: true
        )

        XCTAssertEqual(input, self.input(inputMonitoring: false, sources: 7, slots: 7, bound: 5, detectable: 7, confirmed: true))
        XCTAssertEqual(input.boundSlotCount, SetupGuideState.automaticTriggerLimit)
        XCTAssertTrue(SetupGuideState(input).hasUnboundSlots)
        XCTAssertTrue(SetupGuideInput(
            config: config.completingSetup(), sources: sources,
            accessibilityGranted: true, inputMonitoringGranted: true, listenerRunning: true, hasConfirmedSlots: false
        ).hasCompletedSetup)
    }

    // MARK: Trigger phrases and try-it progress

    func testPhrasesCoverTapDoubleTapAndChord() {
        let tap = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        let doubleTap = KeyTrigger(kind: .oneShotModifier, keyCode: 61, keyName: "right-option", gesture: .doubleTap)
        let chord = KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option, .command])
        let functionKey = KeyTrigger(kind: .keyPress, keyCode: 122, keyName: "f1", modifiers: [.capsLock])

        XCTAssertEqual(SetupTriggerPhrase(trigger: tap).instruction, "Tap Left Command alone")
        XCTAssertEqual(SetupTriggerPhrase(trigger: doubleTap).instruction, "Double-tap Right Option alone")
        XCTAssertEqual(SetupTriggerPhrase(trigger: chord).instruction, "Press Command + Option + J")
        XCTAssertEqual(SetupTriggerPhrase(trigger: functionKey).instruction, "Press Caps Lock + F1")
        for (keyCode, keyName) in [(27, "-"), (24, "="), (33, "[")] {
            let punctuation = KeyTrigger(kind: .keyPress, keyCode: keyCode, keyName: keyName, modifiers: [.control])
            XCTAssertEqual(SetupTriggerPhrase(trigger: punctuation).instruction, "Press Control + \(keyName)")
        }
        XCTAssertFalse(tap.isOneShotShift)
        XCTAssertTrue(KeyTrigger(kind: .oneShotModifier, keyCode: 60, keyName: "right-shift").isOneShotShift)
        XCTAssertFalse(KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.shift]).isOneShotShift)
    }

    func testTryItProgressWalksBoundSlotsInSlotOrder() throws {
        var config = SwitcherConfig.detected(from: ["en", "ko", "ja"].map { source($0) })
        let ids = config.slots.map(\.id)
        config.bindings.removeAll { $0.action.role == ids[1] }
        config.bindings.append(KeyBinding(
            trigger: KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option]),
            action: .switchInputSource(ids[0])
        ))

        let sources = ["en", "ko", "ja"].map { source($0) }
        let start = SetupTryItProgress(config: config, sources: sources, evidence: SetupTriggerEvidence())
        let partial = SetupTryItProgress(config: config, sources: sources,
                                        evidence: evidence(for: [ids[0], InputRole(rawValue: "removed")], config: config, sources: sources))
        let done = SetupTryItProgress(config: config, sources: sources,
                                     evidence: evidence(for: [ids[0], ids[2]], config: config, sources: sources))

        XCTAssertEqual(start.boundSlots, [ids[0], ids[2]])
        XCTAssertEqual(start.nextSlot, ids[0])
        XCTAssertEqual(partial.triedSlots, [ids[0]])
        XCTAssertEqual(partial.nextSlot, ids[2])
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(done.isComplete)
        XCTAssertTrue(start.unmatchedSlots.isEmpty)
        config.bindings.removeAll()
        XCTAssertFalse(SetupTryItProgress(config: config, sources: sources, evidence: SetupTriggerEvidence()).isComplete)
    }

    func testTryItProgressLeavesOutBoundSlotsWithoutAnInputSource() {
        // Legacy defaults bind English, Chinese and Japanese (Option+J); only two are installed.
        let config = SwitcherConfig.default
        let sources = [source("en"), source("zh-Hans")]

        let start = SetupTryItProgress(config: config, sources: sources, evidence: SetupTriggerEvidence())
        let done = SetupTryItProgress(config: config, sources: sources,
                                     evidence: evidence(for: [.english, .chinese, .japanese], config: config, sources: sources))
        let nothingInstalled = SetupTryItProgress(config: config, sources: [], evidence: SetupTriggerEvidence())

        XCTAssertEqual(start.boundSlots, [.english, .chinese])
        XCTAssertEqual(start.unmatchedSlots, [.japanese])
        XCTAssertEqual(done.triedSlots, [.english, .chinese])
        XCTAssertTrue(done.isComplete)
        XCTAssertTrue(nothingInstalled.boundSlots.isEmpty)
        XCTAssertEqual(nothingInstalled.unmatchedSlots, [.english, .chinese, .japanese])
        XCTAssertFalse(nothingInstalled.isComplete)
    }

    func testTryEvidenceRequiresTheCurrentTriggerAndConfirmedSource() throws {
        let sources = [source("en"), source("ko")]
        let config = SwitcherConfig.detected(from: sources)
        let slot = config.slots[0].id
        let trigger = try XCTUnwrap(config.slotTriggers.first?.trigger)
        let empty = SetupTriggerEvidence()
        for event in [
            SetupTriggeredSwitch(slotID: slot, sourceID: "wrong", trigger: trigger),
            SetupTriggeredSwitch(slotID: slot, sourceID: sources[0].id, trigger: try ShortcutParser.parse("option+j")),
            SetupTriggeredSwitch(slotID: InputRole(rawValue: "missing"), sourceID: sources[0].id, trigger: trigger),
        ] {
            XCTAssertEqual(empty.recording(event, config: config, sources: sources), empty)
        }
        let event = SetupTriggeredSwitch(slotID: slot, sourceID: sources[0].id, trigger: trigger)
        XCTAssertEqual(empty.recording(event, config: config, sources: sources).triedSlotIDs(config: config, sources: sources), [slot])
        XCTAssertTrue(empty.triedSlotIDs(config: config, sources: sources).isEmpty)
    }

    func testTryEvidenceDoesNotReviveWhenDeletedSlotIDIsRecreatedIdentically() throws {
        let sources = [source("en"), source("ko")]
        let config = SwitcherConfig.detected(from: sources)
        let ids = config.slots.map(\.id)
        let tried = evidence(for: ids, config: config, sources: sources)
        let removed = try config.removingSlot(ids[0])
        let reconciled = tried.reconciling(config: removed, sources: sources)
        let recreated = try removed.addingSlot(for: sources[0])
        XCTAssertEqual(recreated.slot.id, ids[0])
        XCTAssertEqual(SetupTriggerFingerprint(slotID: ids[0], config: recreated.config, sources: sources),
                       SetupTriggerFingerprint(slotID: ids[0], config: config, sources: sources))
        XCTAssertEqual(reconciled.triedSlotIDs(config: recreated.config, sources: sources), [ids[1]])
        XCTAssertFalse(SetupTryItProgress(config: recreated.config, sources: sources, evidence: reconciled).isComplete)
    }

    func testTryEvidenceInvalidatesChangedTriggerAndKeepsOtherSlots() throws {
        let sources = [source("en"), source("ko")]
        let config = SwitcherConfig.detected(from: sources)
        let ids = config.slots.map(\.id)
        let tried = evidence(for: ids, config: config, sources: sources)
        var changed = config
        changed.upsertSwitchBinding(trigger: try ShortcutParser.parse("option+j"), role: ids[0])
        let reconciled = tried.reconciling(config: changed, sources: sources)
        XCTAssertEqual(reconciled.triedSlotIDs(config: changed, sources: sources), [ids[1]])
        // Reverting later is not a new successful trigger event either.
        XCTAssertEqual(reconciled.triedSlotIDs(config: config, sources: sources), [ids[1]])
    }

    func testTryEvidenceInvalidatesChangedPreferenceOrResolvedInputSource() throws {
        let sources = [source("en"), source("ko")]
        let alternate = source("en", id: "alternate.english")
        let config = SwitcherConfig.detected(from: sources)
        let ids = config.slots.map(\.id)
        let tried = evidence(for: ids, config: config, sources: sources)
        let changed = try config.assigningInputSource(alternate, to: ids[0])
        XCTAssertEqual(tried.triedSlotIDs(config: changed, sources: sources + [alternate]), [ids[1]])
        // Same preference, but its missing preferred source now resolves to a fallback.
        XCTAssertEqual(tried.triedSlotIDs(config: config, sources: [alternate, sources[1]]), [ids[1]])
        var changedRules = config
        changedRules.inputSources[ids[0].rawValue]?.nameContains = ["Changed rules"]
        XCTAssertEqual(tried.triedSlotIDs(config: changedRules, sources: sources), [ids[1]])
    }

    func testTryEvidenceSurvivesUnrelatedStyleNameAndOrderChanges() throws {
        let sources = [source("en"), source("ko")]
        let config = SwitcherConfig.detected(from: sources)
        let ids = config.slots.map(\.id)
        let tried = evidence(for: ids, config: config, sources: sources)
        var changed = try config.renamingSlot(ids[0], to: "Work")
        changed = try changed.settingSlotTint("#123456", for: ids[0])
        changed.showSwitchIndicator.toggle()
        changed.slots.reverse()
        XCTAssertEqual(tried.reconciling(config: changed, sources: sources), tried)
        XCTAssertEqual(tried.triedSlotIDs(config: changed, sources: sources), Set(ids))
        XCTAssertTrue(SetupTryItProgress(config: changed, sources: sources, evidence: tried).isComplete)
    }
}
