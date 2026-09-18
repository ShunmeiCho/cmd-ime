import XCTest
@testable import KeyboardSwitcherCore

#if os(macOS)
final class EventTapMonitorTests: XCTestCase {
    func testActiveEventTapMaskIncludesKeyboardAndExcludesMouseEvents() {
        let mask = EventTapMonitor.eventTapEventMask

        for keyboardType in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            XCTAssertNotEqual(mask & CGEventMask(1 << keyboardType.rawValue), 0)
        }
        for mouseType in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            XCTAssertEqual(mask & CGEventMask(1 << mouseType.rawValue), 0)
        }
    }

    func testStopRemovesMouseDownMonitors() {
        let globalToken = NSObject()
        let localToken = NSObject()
        var installedMasks: [NSEvent.EventTypeMask] = []
        var localHandler: ((NSEvent) -> NSEvent?)?
        var removedTokens: [AnyObject] = []
        let monitor = EventTapMonitor(
            config: .default,
            inputSources: StubInputSourceService(),
            addGlobalMouseDownMonitor: { mask, _ in
                installedMasks.append(mask)
                return globalToken
            },
            addLocalMouseDownMonitor: { mask, handler in
                installedMasks.append(mask)
                localHandler = handler
                return localToken
            },
            removeMouseDownMonitor: { monitor in
                removedTokens.append(monitor as AnyObject)
            }
        )

        monitor.installMouseDownMonitor()
        monitor.installMouseDownMonitor()
        let event = makeLeftMouseDownEvent()
        XCTAssertTrue(localHandler?(event) === event)
        monitor.stop()

        XCTAssertEqual(installedMasks, [EventTapMonitor.mouseDownEventMask, EventTapMonitor.mouseDownEventMask])
        XCTAssertEqual(removedTokens.count, 2)
        XCTAssertTrue(removedTokens[0] === globalToken)
        XCTAssertTrue(removedTokens[1] === localToken)
    }

    #if DEBUG
    func testCachedFallbackRecoversPreferredSourceWithoutRefreshingOtherSlots() {
        let originalSources = makeSwitchSources()
        let preferred = originalSources[1]
        let fallback = InputSourceInfo(
            id: "fallback.japanese", localizedName: "Fallback Japanese",
            languages: ["ja"], isSelectCapable: true
        )
        let service = StubInputSourceService(sources: [originalSources[0], fallback])
        let monitor = EventTapMonitor(config: .default, inputSources: service)
        var reportedSources: [InputSourceInfo] = []
        monitor.onSwitch = { _, source in reportedSources.append(source) }
        monitor.updateConfig(.default)

        triggerJapaneseSwitch(monitor)
        XCTAssertEqual(service.selectedIDs, [fallback.id])
        let readsBeforeRecovery = service.listCallCount

        let renamedEnglish = InputSourceInfo(
            id: originalSources[0].id, localizedName: "Renamed English",
            languages: ["en"], isSelectCapable: true
        )
        service.sources = [renamedEnglish, fallback, preferred]
        triggerJapaneseSwitch(monitor)
        XCTAssertEqual(service.selectedIDs, [fallback.id, preferred.id])
        XCTAssertEqual(service.listCallCount, readsBeforeRecovery + 1)

        // Recovery must not replace even the metadata cached for unrelated slots.
        monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()
        XCTAssertEqual(reportedSources.last?.localizedName, originalSources[0].localizedName)
        XCTAssertEqual(service.listCallCount, readsBeforeRecovery + 1)
    }

    func testCachedFirstPreferredIDDoesNotRelistSources() {
        let service = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: service)
        monitor.updateConfig(.default)
        let initialReads = service.listCallCount

        triggerJapaneseSwitch(monitor)
        triggerJapaneseSwitch(monitor)

        XCTAssertEqual(service.selectedIDs, Array(repeating: makeSwitchSources()[1].id, count: 2))
        XCTAssertEqual(service.listCallCount, initialReads)
    }

    func testCachedSecondaryPreferredIDKeepsStaticMatcherResult() {
        let fallback = InputSourceInfo(
            id: "com.apple.inputmethod.Kotoeri.RomajiTyping", localizedName: "Japanese",
            languages: ["ja"], isSelectCapable: true
        )
        let service = StubInputSourceService(sources: [fallback])
        let monitor = EventTapMonitor(config: .default, inputSources: service)
        monitor.updateConfig(.default)
        let initialReads = service.listCallCount

        triggerJapaneseSwitch(monitor)
        triggerJapaneseSwitch(monitor)

        XCTAssertEqual(service.selectedIDs, [fallback.id, fallback.id])
        XCTAssertEqual(service.listCallCount, initialReads + 2)
    }

    private func triggerJapaneseSwitch(_ monitor: EventTapMonitor) {
        XCTAssertNil(monitor.handleKeyDownForTesting(makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])))
        XCTAssertNil(monitor.handleKeyUpForTesting(makeKeyboardEvent(keyCode: 38, keyDown: false)))
        drainMainQueue()
    }

    func testShortcutCapturePassesBoundChordAndKeyUpThenResumesConsumption() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in switchedRoles.append(role) }
        let down = makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])
        let up = makeKeyboardEvent(keyCode: 38, keyDown: false)

        monitor.isCapturingShortcut = true
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58, flags: [.maskAlternate]))
        XCTAssertTrue(monitor.handleKeyDownForTesting(down)?.takeUnretainedValue() === down)
        // Committing a recording can end capture before the physical key is released.
        monitor.isCapturingShortcut = false
        XCTAssertTrue(monitor.handleKeyUpForTesting(up)?.takeUnretainedValue() === up)
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58))
        drainMainQueue()
        XCTAssertEqual(switchedRoles, [])
        XCTAssertEqual(inputSources.selectedIDs, [])

        XCTAssertNil(monitor.handleKeyDownForTesting(down))
        XCTAssertNil(monitor.handleKeyUpForTesting(up))
        drainMainQueue()
        XCTAssertEqual(switchedRoles, [.japanese])
        XCTAssertEqual(inputSources.selectedIDs, ["com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"])
    }

    func testShortcutCaptureStillCancelsOneShotAndPassesRemap() throws {
        var config = SwitcherConfig.default
        let chord = try ShortcutParser.parse("command+k")
        config.upsertRemapBinding(trigger: chord, output: try ShortcutParser.parse("a"))
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: config, inputSources: inputSources)
        let down = makeKeyboardEvent(keyCode: 40, flags: [.maskCommand])
        let up = makeKeyboardEvent(keyCode: 40, keyDown: false)
        monitor.isCapturingShortcut = true
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        XCTAssertTrue(monitor.handleKeyDownForTesting(down)?.takeUnretainedValue() === down)
        XCTAssertTrue(monitor.handleKeyUpForTesting(up)?.takeUnretainedValue() === up)
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()
        XCTAssertEqual(inputSources.selectedIDs, [])
    }

    func testShortcutCapturePassesReleaseOfPreviouslyConsumedRepeatingKey() {
        let monitor = EventTapMonitor(config: .default, inputSources: StubInputSourceService())
        let down = makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])
        let up = makeKeyboardEvent(keyCode: 38, keyDown: false)
        XCTAssertNil(monitor.handleKeyDownForTesting(down))
        monitor.isCapturingShortcut = true
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(monitor.handleKeyDownForTesting(down)?.takeUnretainedValue() === down)
        monitor.isCapturingShortcut = false
        XCTAssertTrue(monitor.handleKeyUpForTesting(up)?.takeUnretainedValue() === up)
    }

    func testCustomSlotSwitchAndDuplicateIDsRemainSafe() throws {
        let source = InputSourceInfo(id: "custom.korean", localizedName: "Korean", languages: ["ko"], isSelectCapable: true)
        let added = try SwitcherConfig(bindings: [], inputSources: [:]).addingSlot(for: source)
        var config = added.config
        config.slots.append(added.slot)
        let service = StubInputSourceService(sources: [source])
        let monitor = EventTapMonitor(config: config, inputSources: service)
        var roles: [InputRole] = []
        monitor.onSwitch = { role, _ in roles.append(role) }
        monitor.updateConfig(config)
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()
        XCTAssertEqual(service.selectedIDs, [source.id])
        XCTAssertEqual(roles, [added.slot.id])
    }

    func testMouseDownMonitorsCancelPendingOneShotModifier() {
        var globalHandler: ((NSEvent) -> Void)?
        var localHandler: ((NSEvent) -> NSEvent?)?
        let monitor = EventTapMonitor(
            config: .default,
            inputSources: StubInputSourceService(),
            addGlobalMouseDownMonitor: { _, handler in
                globalHandler = handler
                return NSObject()
            },
            addLocalMouseDownMonitor: { _, handler in
                localHandler = handler
                return NSObject()
            },
            removeMouseDownMonitor: { _ in }
        )
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command")
        let event = makeLeftMouseDownEvent()

        monitor.installMouseDownMonitor()
        monitor.setOneShotModifierDownForTesting(trigger)
        globalHandler?(event)

        XCTAssertEqual(monitor.releaseOneShotModifierForTesting(trigger), .wait)

        monitor.setOneShotModifierDownForTesting(trigger)
        XCTAssertTrue(localHandler?(event) === event)

        XCTAssertEqual(monitor.releaseOneShotModifierForTesting(trigger), .wait)
    }

    func testUnboundModifierShortcutDoesNotPoisonNextOneShotModifier() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58, flags: [.maskAlternate]))
        XCTAssertNil(monitor.handleKeyDownForTesting(makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])))
        XCTAssertNil(monitor.handleKeyUpForTesting(makeKeyboardEvent(keyCode: 38, keyDown: false)))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58))
        drainMainQueue()

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()

        XCTAssertEqual(switchedRoles, [.japanese, .english])
        XCTAssertEqual(
            inputSources.selectedIDs,
            [
                "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                "com.apple.keylayout.ABC",
            ]
        )
    }

    func testRightUnboundModifierShortcutDoesNotPoisonNextOneShotModifier() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertNil(monitor.handleKeyDownForTesting(makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])))
        XCTAssertNil(monitor.handleKeyUpForTesting(makeKeyboardEvent(keyCode: 38, keyDown: false)))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 61))
        drainMainQueue()

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54))
        drainMainQueue()

        XCTAssertEqual(switchedRoles, [.japanese, .chinese])
        XCTAssertEqual(
            inputSources.selectedIDs,
            [
                "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                "com.apple.inputmethod.SCIM.ITABC",
            ]
        )
    }

    func testModifierChordStillCancelsOneShotAfterUnboundModifierShortcut() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58, flags: [.maskAlternate]))
        XCTAssertNil(monitor.handleKeyDownForTesting(makeKeyboardEvent(keyCode: 38, flags: [.maskAlternate])))
        XCTAssertNil(monitor.handleKeyUpForTesting(makeKeyboardEvent(keyCode: 38, keyDown: false)))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58))
        drainMainQueue()

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleKeyDownForTesting(makeKeyboardEvent(keyCode: 8, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()

        XCTAssertEqual(switchedRoles, [.japanese])
        XCTAssertEqual(inputSources.selectedIDs, ["com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"])
    }

    func testRightCommandReleaseWhileLeftCommandHeldIsTrackedAsRelease() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        XCTAssertEqual(monitor.pressedModifierKeyCodesForTesting, [54, 55])

        // Aggregate .maskCommand stays set because left-command is still held.
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        XCTAssertEqual(monitor.pressedModifierKeyCodesForTesting, [55])

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        XCTAssertEqual(monitor.pressedModifierKeyCodesForTesting, [])
        XCTAssertEqual(switchedRoles, [])

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54))
        drainMainQueue()

        XCTAssertEqual(switchedRoles, [.chinese])
        XCTAssertEqual(inputSources.selectedIDs, ["com.apple.inputmethod.SCIM.ITABC"])
    }

    func testTapWhileOppositeCommandPhysicallyHeldIsChord() {
        var globalHandler: ((NSEvent) -> Void)?
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        let monitor = EventTapMonitor(
            config: .default,
            inputSources: inputSources,
            addGlobalMouseDownMonitor: { _, handler in
                globalHandler = handler
                return NSObject()
            },
            addLocalMouseDownMonitor: { _, _ in NSObject() },
            removeMouseDownMonitor: { _ in }
        )
        var switchedRoles: [InputRole] = []
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
        }
        monitor.installMouseDownMonitor()

        // Right-command held, a click cancels the pending one-shot, then left-command
        // is tapped while right-command is still physically down.
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        globalHandler?(makeLeftMouseDownEvent())
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54))
        drainMainQueue()

        XCTAssertEqual(switchedRoles, [])
        XCTAssertEqual(inputSources.selectedIDs, [])
        XCTAssertEqual(monitor.pressedModifierKeyCodesForTesting, [])
    }

    func testClearedAggregateFlagResyncsBothSidesOfModifier() {
        let monitor = EventTapMonitor(config: .default, inputSources: StubInputSourceService())

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 58, flags: [.maskCommand, .maskAlternate]))
        // A missed left-command release: the next command event arrives with the flag cleared.
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskAlternate]))

        XCTAssertEqual(monitor.pressedModifierKeyCodesForTesting, [58])
    }

    func testSwitchLeavesTapCallbackAndReportsOnlyAfterConfirmation() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        inputSources.unconfirmedReads["com.apple.keylayout.ABC"] = 1
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        let switched = expectation(description: "english confirmed")
        monitor.onSwitch = { role, source in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(role, .english)
            inputSources.log.append("onSwitch:\(source.id)")
            switched.fulfill()
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        // The tap callback returned without touching the input source service.
        XCTAssertEqual(inputSources.log, [])

        wait(for: [switched], timeout: 1)
        XCTAssertEqual(
            inputSources.log,
            [
                "select:com.apple.keylayout.ABC",
                "current:nil",
                "current:com.apple.keylayout.ABC",
                "onSwitch:com.apple.keylayout.ABC",
            ]
        )
    }

    func testNewerSwitchSupersedesPendingRetriesOfOlderSwitch() {
        let inputSources = StubInputSourceService(sources: makeSwitchSources())
        inputSources.unconfirmedReads["com.apple.keylayout.ABC"] = 1
        let monitor = EventTapMonitor(config: .default, inputSources: inputSources)
        var switchedRoles: [InputRole] = []
        let chineseSwitched = expectation(description: "chinese confirmed")
        let englishSwitched = expectation(description: "superseded english never reported")
        englishSwitched.isInverted = true
        monitor.onSwitch = { role, _ in
            switchedRoles.append(role)
            if role == .chinese {
                chineseSwitched.fulfill()
            } else {
                englishSwitched.fulfill()
            }
        }

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 55))
        drainMainQueue()
        // English was selected but not yet confirmed, so a retry is pending.
        XCTAssertEqual(inputSources.log, ["select:com.apple.keylayout.ABC", "current:nil"])

        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54, flags: [.maskCommand]))
        _ = monitor.handleFlagsChangedForTesting(makeKeyboardEvent(keyCode: 54))

        wait(for: [chineseSwitched], timeout: 1)
        // Well past the English retry delay: the stale retry must not reselect or report.
        wait(for: [englishSwitched], timeout: 0.2)
        XCTAssertEqual(switchedRoles, [.chinese])
        XCTAssertEqual(
            inputSources.selectedIDs,
            ["com.apple.keylayout.ABC", "com.apple.inputmethod.SCIM.ITABC"]
        )
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 1)
    }
    #endif

    func testKeyPressFlagsIgnoreUnexpectedCapsLockAndFn() {
        let monitor = EventTapMonitor(config: .default)

        XCTAssertTrue(monitor.eventFlags([.maskAlternate, .maskAlphaShift], contain: [.option]))
        XCTAssertTrue(monitor.eventFlags([.maskAlternate, .maskSecondaryFn], contain: [.option]))
        XCTAssertFalse(monitor.eventFlags([.maskAlternate, .maskCommand], contain: [.option]))
    }

    func testKeyPressFlagsCanRequireCapsLockOrFnWhenConfigured() {
        let monitor = EventTapMonitor(config: .default)

        XCTAssertTrue(monitor.eventFlags([.maskAlternate, .maskAlphaShift], contain: [.option, .capsLock]))
        XCTAssertTrue(monitor.eventFlags([.maskAlternate, .maskSecondaryFn], contain: [.option, .fn]))
        XCTAssertFalse(monitor.eventFlags([.maskAlternate], contain: [.option, .fn]))
    }
}

private func makeLeftMouseDownEvent() -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    )!
}

private func makeKeyboardEvent(keyCode: Int, flags: CGEventFlags = [], keyDown: Bool = true) -> CGEvent {
    let event = CGEvent(
        keyboardEventSource: nil,
        virtualKey: CGKeyCode(keyCode),
        keyDown: keyDown
    )!
    event.flags = flags
    return event
}

private func makeSwitchSources() -> [InputSourceInfo] {
    [
        InputSourceInfo(
            id: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            languages: ["en"],
            isSelectCapable: true
        ),
        InputSourceInfo(
            id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            localizedName: "Hiragana",
            languages: ["ja"],
            isSelectCapable: true
        ),
        InputSourceInfo(
            id: "com.apple.inputmethod.SCIM.ITABC",
            localizedName: "Pinyin - Simplified",
            languages: ["zh-Hans"],
            isSelectCapable: true
        ),
    ]
}

private final class StubInputSourceService: InputSourceService {
    var sources: [InputSourceInfo]
    private(set) var listCallCount = 0
    private var selectedID: String?
    private(set) var selectedIDs: [String] = []
    /// Per id, how many `currentInputSource()` reads after selecting it still return nil.
    var unconfirmedReads: [String: Int] = [:]
    var log: [String] = []

    init(sources: [InputSourceInfo] = []) {
        self.sources = sources
    }

    func listInputSources() throws -> [InputSourceInfo] {
        listCallCount += 1
        return sources
    }

    func currentInputSource() throws -> InputSourceInfo? {
        if let selectedID, let lag = unconfirmedReads[selectedID], lag > 0 {
            unconfirmedReads[selectedID] = lag - 1
            log.append("current:nil")
            return nil
        }
        let current = sources.first { $0.id == selectedID }
        log.append("current:\(current?.id ?? "nil")")
        return current
    }

    func selectInputSource(id: String) throws {
        selectedID = id
        selectedIDs.append(id)
        log.append("select:\(id)")
    }
}
#endif
