import XCTest
@testable import KeyboardSwitcherCore

final class SetupGuideTests: XCTestCase {
    private func source(_ language: String, id: String? = nil, selectable: Bool = true) -> InputSourceInfo {
        InputSourceInfo(id: id ?? "source.\(language)", localizedName: "Source \(id ?? language)", languages: [language], isSelectCapable: selectable)
    }

    private func temporaryStore() -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ConfigStore(url: directory.appendingPathComponent("config.json"))
    }

    private func input(
        accessibility: Bool = true,
        inputMonitoring: Bool = true,
        listenerFailed: Bool = false,
        sources: Int = 2,
        slots: Int = 2,
        bound: Int = 2,
        confirmed: Bool = false,
        completed: Bool = false
    ) -> SetupGuideInput {
        SetupGuideInput(
            accessibilityGranted: accessibility,
            inputMonitoringGranted: inputMonitoring,
            listenerFailed: listenerFailed,
            selectableSourceCount: sources,
            slotCount: slots,
            boundSlotCount: bound,
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

    // MARK: Edge flags

    func testNeedsMoreSourcesBelowTwoSelectableSources() {
        XCTAssertTrue(SetupGuideState(input(sources: 0)).needsMoreSources)
        XCTAssertTrue(SetupGuideState(input(sources: 1)).needsMoreSources)
        XCTAssertFalse(SetupGuideState(input(sources: 2)).needsMoreSources)
        XCTAssertEqual(SetupGuideState(input(sources: 1)).currentStep, .review)
    }

    func testSlotsBeyondAutomaticTriggersNeedsMoreThanFiveSlotsAndAnUnboundOne() {
        XCTAssertTrue(SetupGuideState(input(sources: 6, slots: 6, bound: 5)).hasSlotsBeyondAutomaticTriggers)
        XCTAssertFalse(SetupGuideState(input(sources: 6, slots: 6, bound: 6)).hasSlotsBeyondAutomaticTriggers)
        XCTAssertFalse(SetupGuideState(input(sources: 5, slots: 5, bound: 5)).hasSlotsBeyondAutomaticTriggers)
        XCTAssertFalse(SetupGuideState(input(sources: 8, slots: 3, bound: 2)).hasSlotsBeyondAutomaticTriggers)
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
            hasConfirmedSlots: true
        )

        XCTAssertEqual(input, self.input(inputMonitoring: false, sources: 7, slots: 7, bound: 5, confirmed: true))
        XCTAssertEqual(input.boundSlotCount, SetupGuideState.automaticTriggerLimit)
        XCTAssertTrue(SetupGuideState(input).hasSlotsBeyondAutomaticTriggers)
        XCTAssertTrue(SetupGuideInput(
            config: config.completingSetup(), sources: sources,
            accessibilityGranted: true, inputMonitoringGranted: true, hasConfirmedSlots: false
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

        let start = SetupTryItProgress(config: config, tried: [])
        let partial = SetupTryItProgress(config: config, tried: [ids[0], InputRole(rawValue: "removed")])
        let done = SetupTryItProgress(config: config, tried: [ids[0], ids[2]])

        XCTAssertEqual(start.boundSlots, [ids[0], ids[2]])
        XCTAssertEqual(start.nextSlot, ids[0])
        XCTAssertEqual(partial.triedSlots, [ids[0]])
        XCTAssertEqual(partial.nextSlot, ids[2])
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(done.isComplete)
        config.bindings.removeAll()
        XCTAssertFalse(SetupTryItProgress(config: config, tried: []).isComplete)
    }
}
