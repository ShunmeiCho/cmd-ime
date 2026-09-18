import XCTest
@testable import KeyboardSwitcherCore

final class SetupGuideTests: XCTestCase {
    private func source(_ language: String, selectable: Bool = true) -> InputSourceInfo {
        InputSourceInfo(id: "source.\(language)", localizedName: "Source \(language)", languages: [language], isSelectCapable: selectable)
    }

    private func input(
        accessibility: Bool = true,
        inputMonitoring: Bool = true,
        sources: Int = 2,
        slots: Int = 2,
        bound: Int = 2,
        confirmed: Bool = false,
        completed: Bool = false
    ) -> SetupGuideInput {
        SetupGuideInput(
            accessibilityGranted: accessibility,
            inputMonitoringGranted: inputMonitoring,
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
}
