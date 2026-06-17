#if os(macOS)
import AppKit
import Carbon
import Foundation

public final class EventTapMonitor: @unchecked Sendable {
    public var config: SwitcherConfig
    public var onMessage: ((String) -> Void)?

    private let inputSources: InputSourceService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var oneShotState = OneShotModifierState()
    private var consumedKeyDowns = Set<Int>()
    private var resolvedSources: [InputRole: InputSourceInfo] = [:]
    private var pendingSingleTapTimer: Timer?

    public init(config: SwitcherConfig, inputSources: InputSourceService = MacInputSourceService()) {
        self.config = config
        self.inputSources = inputSources
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

        let eventTypes: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, eventType in
            mask | CGEventMask(1 << eventType.rawValue)
        }

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
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
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            oneShotState.cancel()
            return Unmanaged.passUnretained(event)
        default:
            oneShotState.cancel()
            return Unmanaged.passUnretained(event)
        }
    }

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
            hasDoubleTapBinding: hasDoubleTapBinding(for: trigger),
            delaysSingleTap: config.protectDoubleTapShortcuts
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
        case 57:
            KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: "caps-lock")
        default:
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
                    onMessage?("No input source matched \(role.rawValue).")
                    return
                }
                do {
                    try inputSources.selectInputSource(id: source.id)
                    onMessage?("Selected \(source.localizedName) for \(role.rawValue).")
                } catch {
                    refreshResolvedSources()
                    if let fallback = resolvedSources[role] {
                        try inputSources.selectInputSource(id: fallback.id)
                        onMessage?("Selected \(fallback.localizedName) for \(role.rawValue).")
                    } else {
                        throw error
                    }
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

    private func eventFlags(_ flags: CGEventFlags, contain modifiers: [Modifier]) -> Bool {
        let expected = Set(modifiers)
        let actual = Set(Modifier.allCases.filter { flags.contains(cgFlag(for: $0)) })
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
