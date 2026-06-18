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

private final class StubInputSourceService: InputSourceService {
    func listInputSources() throws -> [InputSourceInfo] {
        []
    }

    func currentInputSource() throws -> InputSourceInfo? {
        nil
    }

    func selectInputSource(id _: String) throws {}
}
#endif
