#if os(macOS)
import AppKit
import Carbon
import Foundation

public final class EventTapMonitor: @unchecked Sendable {
    public var config: SwitcherConfig
    public var onMessage: ((String) -> Void)?
    public var onSwitch: ((InputRole, InputSourceInfo) -> Void)?

    private let inputSources: InputSourceService
    private let addGlobalMouseDownMonitor: GlobalMouseDownMonitorInstaller
    private let addLocalMouseDownMonitor: LocalMouseDownMonitorInstaller
    private let removeMouseDownMonitor: MouseDownMonitorRemover
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseDownMonitors: [Any] = []
    private var oneShotState = OneShotModifierState()
    private var consumedKeyDowns = Set<Int>()
    private var resolvedSources: [InputRole: InputSourceInfo] = [:]
    private var pendingSingleTapTimer: Timer?
    private let eventTapConfirmationRetryDelays: [TimeInterval] = [0.01]

    typealias GlobalMouseDownMonitorInstaller = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias LocalMouseDownMonitorInstaller = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
    typealias MouseDownMonitorRemover = (Any) -> Void

    static let eventTapEventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged,
    ]

    static let eventTapEventMask: CGEventMask = eventTapEventTypes.reduce(CGEventMask(0)) { mask, eventType in
        mask | CGEventMask(1 << eventType.rawValue)
    }

    static let mouseDownEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
    ]

    public convenience init(config: SwitcherConfig, inputSources: InputSourceService = MacInputSourceService()) {
        self.init(
            config: config,
            inputSources: inputSources,
            addGlobalMouseDownMonitor: NSEvent.addGlobalMonitorForEvents,
            addLocalMouseDownMonitor: NSEvent.addLocalMonitorForEvents,
            removeMouseDownMonitor: NSEvent.removeMonitor
        )
    }

    init(
        config: SwitcherConfig,
        inputSources: InputSourceService,
        addGlobalMouseDownMonitor: @escaping GlobalMouseDownMonitorInstaller,
        addLocalMouseDownMonitor: @escaping LocalMouseDownMonitorInstaller,
        removeMouseDownMonitor: @escaping MouseDownMonitorRemover
    ) {
        self.config = config
        self.inputSources = inputSources
        self.addGlobalMouseDownMonitor = addGlobalMouseDownMonitor
        self.addLocalMouseDownMonitor = addLocalMouseDownMonitor
        self.removeMouseDownMonitor = removeMouseDownMonitor
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    public func start() throws {
        guard eventTap == nil else {
            return
        }

        guard MacPermissionStatus.current().isReady else {
            throw EventTapError.missingPermissions
        }

        refreshResolvedSources()

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventTapEventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<EventTapMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            throw EventTapError.failedToCreateEventTap
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installMouseDownMonitor()
        onMessage?("Listener started.")
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        removeMouseDownMonitors()
        oneShotState.cancel()
        pendingSingleTapTimer?.invalidate()
        pendingSingleTapTimer = nil
        consumedKeyDowns.removeAll()
    }

    public func updateConfig(_ config: SwitcherConfig) {
        self.config = config
        refreshResolvedSources()
    }

    private func refreshResolvedSources() {
        do {
            let sources = try inputSources.listInputSources()
            resolvedSources = Dictionary(
                uniqueKeysWithValues: InputRole.allCases.compactMap { role in
                    guard let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config) else {
                        return nil
                    }
                    return (role, source)
                }
            )
        } catch {
            resolvedSources.removeAll()
            onMessage?("Input source refresh failed: \(error.localizedDescription)")
        }
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            oneShotState.cancel()
            return Unmanaged.passUnretained(event)
        }
    }

    func installMouseDownMonitor() {
        guard mouseDownMonitors.isEmpty else {
            return
        }

        if let globalMonitor = addGlobalMouseDownMonitor(Self.mouseDownEventMask, { [weak self] _ in
            self?.cancelOneShotFromMouseDown()
        }) {
            mouseDownMonitors.append(globalMonitor)
        }
        if let localMonitor = addLocalMouseDownMonitor(Self.mouseDownEventMask, { [weak self] event in
            self?.cancelOneShotFromMouseDown()
            return event
        }) {
            mouseDownMonitors.append(localMonitor)
        }
    }

    private func cancelOneShotFromMouseDown() {
        if Thread.isMainThread {
            oneShotState.cancel()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.oneShotState.cancel()
            }
        }
    }

    func removeMouseDownMonitors() {
        for mouseDownMonitor in mouseDownMonitors {
            removeMouseDownMonitor(mouseDownMonitor)
        }
        mouseDownMonitors.removeAll()
    }

    #if DEBUG
    func setOneShotModifierDownForTesting(_ trigger: KeyTrigger) {
        oneShotState.modifierDown(trigger)
    }

    func releaseOneShotModifierForTesting(_ trigger: KeyTrigger) -> OneShotModifierState.Output {
        oneShotState.modifierUp(trigger)
    }
    #endif

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if let modifierTrigger = modifierTrigger(forKeyCode: keyCode), isModifierDown(for: keyCode, flags: event.flags) {
            oneShotState.modifierDown(modifierTrigger)
        }

        guard let trigger = modifierTrigger(forKeyCode: keyCode), hasOneShotBinding(for: trigger) else {
            return Unmanaged.passUnretained(event)
        }

        if isModifierDown(for: keyCode, flags: event.flags) {
            return Unmanaged.passUnretained(event)
        }

        switch oneShotState.modifierUp(
            trigger,
            hasDoubleTapBinding: hasDoubleTapBinding(for: trigger)
        ) {
        case .trigger(let output):
            pendingSingleTapTimer?.invalidate()
            pendingSingleTapTimer = nil
            if let binding = binding(for: output) {
                perform(binding.action)
            }
        case .wait:
            if binding(for: trigger) != nil || hasDoubleTapBinding(for: trigger) {
                scheduleSingleTapFlush()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        oneShotState.keyDown(keyCode)
        guard let binding = keyPressBinding(forKeyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        perform(binding.action)
        consumedKeyDowns.insert(keyCode)
        return nil
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if consumedKeyDowns.remove(keyCode) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func modifierTrigger(forKeyCode keyCode: Int) -> KeyTrigger? {
        switch keyCode {
        case 54:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "right-command")
        case 55:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "left-command")
        case 58:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "left-option")
        case 61:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "right-option")
        case 59:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "left-control")
        case 62:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "right-control")
        case 56:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "left-shift")
        case 60:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "right-shift")
        default:
            // Caps Lock (57) is intentionally excluded: its CGEventFlags bit is a latch
            // (lock on/off), not a momentary press, so the tap/double-tap one-shot model
            // cannot drive it without corrupting the user's Caps Lock state.
            nil
        }
    }

    private func keyPressBinding(forKeyCode keyCode: Int, flags: CGEventFlags) -> KeyBinding? {
        config.bindings.first { binding in
            binding.enabled
                && binding.trigger.kind == .keyPress
                && binding.trigger.keyCode == keyCode
                && eventFlags(flags, contain: binding.trigger.modifiers)
        }
    }

    private func binding(for trigger: KeyTrigger) -> KeyBinding? {
        config.bindings.first { $0.enabled && $0.trigger == trigger }
    }

    private func hasOneShotBinding(for trigger: KeyTrigger) -> Bool {
        config.bindings.contains {
            $0.enabled
                && $0.trigger.kind == .oneShotModifier
                && $0.trigger.keyCode == trigger.keyCode
        }
    }

    private func hasDoubleTapBinding(for trigger: KeyTrigger) -> Bool {
        var doubleTap = trigger
        doubleTap.gesture = .doubleTap
        return binding(for: doubleTap) != nil
    }

    private func scheduleSingleTapFlush() {
        pendingSingleTapTimer?.invalidate()
        pendingSingleTapTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            if let trigger = self.oneShotState.flushPendingSingleTap(), let binding = self.binding(for: trigger) {
                self.perform(binding.action)
            }
            self.pendingSingleTapTimer = nil
        }
    }

    private func perform(_ action: BindingAction) {
        do {
            switch action.type {
            case .switchInputSource:
                guard let role = action.role else {
                    return
                }
                if resolvedSources[role] == nil {
                    refreshResolvedSources()
                }
                guard let source = resolvedSources[role] else {
                    onMessage?("No input method matched this switch slot.")
                    return
                }
                do {
                    try selectAndReport(source, role: role, prefix: nil)
                } catch {
                    let originalError = error
                    refreshResolvedSources()
                    guard let fallback = resolvedSources[role], fallback.id != source.id else {
                        // No different source to fall back to; surface the real reason
                        // instead of the generic "Action failed".
                        onMessage?("Could not switch this slot: \(originalError.localizedDescription)")
                        return
                    }
                    try selectAndReport(
                        fallback,
                        role: role,
                        prefix: "\(source.localizedName) failed: \(originalError.localizedDescription)"
                    )
                }
            case .sendKey:
                guard let output = action.output else {
                    return
                }
                postKey(output)
            case .disable:
                break
            }
        } catch {
            onMessage?("Action failed: \(error.localizedDescription)")
        }
    }

    private func selectAndReport(_ source: InputSourceInfo, role: InputRole, prefix: String?) throws {
        let current = try inputSources.selectInputSourceAndConfirm(
            id: source.id,
            retryDelays: eventTapConfirmationRetryDelays
        )
        guard current?.id == source.id else {
            onMessage?(InputSourceInfo.verificationMessage(requested: source, current: current))
            return
        }
        onSwitch?(role, source)
        if let prefix {
            onMessage?("\(prefix). Selected refreshed input method \(source.localizedName).")
        } else {
            onMessage?("Selected \(source.localizedName).")
        }
    }

    private func postKey(_ trigger: KeyTrigger) {
        guard trigger.kind == .keyPress else {
            return
        }

        let flags = cgFlags(from: trigger.modifiers)
        let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(trigger.keyCode),
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(trigger.keyCode),
            keyDown: false
        )
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func isModifierDown(for keyCode: Int, flags: CGEventFlags) -> Bool {
        guard let flag = modifierFlag(forKeyCode: keyCode) else {
            return false
        }
        return flags.contains(flag)
    }

    func eventFlags(_ flags: CGEventFlags, contain modifiers: [Modifier]) -> Bool {
        let expected = Set(modifiers)
        let actual = Set(Modifier.allCases.filter { flags.contains(cgFlag(for: $0)) })
            .subtracting(Modifier.latching.subtracting(expected))
        return actual == expected
    }

    private func cgFlags(from modifiers: [Modifier]) -> CGEventFlags {
        modifiers.reduce(CGEventFlags()) { partial, modifier in
            partial.union(cgFlag(for: modifier))
        }
    }

    private func cgFlag(for modifier: Modifier) -> CGEventFlags {
        switch modifier {
        case .command:
            .maskCommand
        case .option:
            .maskAlternate
        case .control:
            .maskControl
        case .shift:
            .maskShift
        case .fn:
            .maskSecondaryFn
        case .capsLock:
            .maskAlphaShift
        }
    }

    private func modifierFlag(forKeyCode keyCode: Int) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            .maskCommand
        case 58, 61:
            .maskAlternate
        case 59, 62:
            .maskControl
        case 56, 60:
            .maskShift
        case 57:
            .maskAlphaShift
        case 63:
            .maskSecondaryFn
        default:
            nil
        }
    }
}

public enum EventTapError: Error, LocalizedError {
    case missingPermissions
    case failedToCreateEventTap

    public var errorDescription: String? {
        switch self {
        case .missingPermissions:
            "Accessibility and Input Monitoring permissions are required before keyboard control can start."
        case .failedToCreateEventTap:
            "Failed to create keyboard event tap. Grant Accessibility and Input Monitoring permissions, then retry."
        }
    }
}
#endif
