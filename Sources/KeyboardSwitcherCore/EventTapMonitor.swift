#if os(macOS)
import AppKit
import Carbon
import Foundation

public final class EventTapMonitor: @unchecked Sendable {
    public var config: SwitcherConfig
    public var onMessage: ((String) -> Void)?
    public var onSwitch: ((InputRole, InputSourceInfo) -> Void)?
    /// A confirmed event-tap switch, including the binding that actually fired.
    public var onTriggeredSwitch: ((InputRole, InputSourceInfo, KeyTrigger) -> Void)?

    /// The event tap runs on the main run loop; recording state must change there too.
    public var isCapturingShortcut: Bool {
        get {
            precondition(Thread.isMainThread)
            return capturingShortcut
        }
        set {
            precondition(Thread.isMainThread)
            guard capturingShortcut != newValue else { return }
            capturingShortcut = newValue
            // Neither half of a gesture may cross a recording boundary.
            oneShotState.cancel()
            pendingSingleTapTimer?.invalidate()
            pendingSingleTapTimer = nil
            modifierEvidenceEpochs.removeAll()
            pendingTapEvidenceEpoch = nil
            if newValue {
                // Also retire actions/retries queued just before the recorder opened.
                switchGeneration &+= 1
            }
        }
    }
    private var capturingShortcut = false

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
    private var sourceSnapshot: [InputSourceInfo]?
    private var pendingSingleTapTimer: Timer?
    private let eventTapConfirmationRetryDelays: [TimeInterval] = [0.01]
    /// Physically held one-shot modifier keys, tracked per keyCode so a left/right
    /// release is not misread while the sibling key keeps the aggregate flag set.
    private var pressedModifierKeyCodes = Set<Int>()
    /// Bumped on every switch request; a switch whose generation is no longer
    /// current abandons its pending start and confirmation retries.
    private var switchGeneration = 0
    private var triggerEvidenceEpoch = UUID()
    private var modifierEvidenceEpochs: [Int: UUID] = [:]
    private var pendingTapEvidenceEpoch: UUID?

    static func scheduleOnMainQueue(after delay: TimeInterval, _ work: @escaping () -> Void) {
        // The event tap and all TIS calls live on the main thread, and `work` only
        // ever runs there, so handing it to the main queue is safe.
        nonisolated(unsafe) let work = work
        if delay <= 0 {
            DispatchQueue.main.async { work() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
        }
    }

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
        pressedModifierKeyCodes.removeAll()
        modifierEvidenceEpochs.removeAll()
        pendingTapEvidenceEpoch = nil
    }

    public func updateConfig(_ config: SwitcherConfig) {
        if Set(self.config.slots.map(\.id)) != Set(config.slots.map(\.id))
            || self.config.bindings != config.bindings || self.config.inputSources != config.inputSources {
            // Invalidate only the new evidence channel; legacy switch delivery is unchanged.
            triggerEvidenceEpoch = UUID()
        }
        self.config = config
        refreshResolvedSources()
    }

    /// Adopts a source list taken outside this process. A long-running process can keep
    /// listing sources the user already removed, so an accepted snapshot replaces the
    /// in-process enumeration for every later resolution until the next snapshot.
    public func updateConfig(_ config: SwitcherConfig, sources: [InputSourceInfo]) {
        sourceSnapshot = sources
        updateConfig(config)
    }

    private func currentSources() throws -> [InputSourceInfo] {
        try sourceSnapshot ?? inputSources.listInputSources()
    }

    private func refreshResolvedSources() {
        do {
            let sources = try currentSources()
            resolvedSources.removeAll()
            for slot in config.slots {
                if let source = InputSourceMatcher.bestMatch(for: slot.id, sources: sources, config: config) {
                    resolvedSources[slot.id] = source
                }
            }
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

    var pressedModifierKeyCodesForTesting: Set<Int> {
        pressedModifierKeyCodes
    }

    @discardableResult
    func handleFlagsChangedForTesting(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        handleFlagsChanged(event)
    }

    @discardableResult
    func handleKeyDownForTesting(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        handleKeyDown(event)
    }

    @discardableResult
    func handleKeyUpForTesting(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        handleKeyUp(event)
    }
    #endif

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let trigger = modifierTrigger(forKeyCode: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        let isPress = recordModifierTransition(keyCode: keyCode, flags: event.flags)
        // Keep physical left/right tracking current, but do not recognize actions
        // while recording. The state machine is cleared at both capture boundaries.
        guard !isCapturingShortcut else {
            return Unmanaged.passUnretained(event)
        }
        if isPress {
            modifierEvidenceEpochs[keyCode] = triggerEvidenceEpoch
            oneShotState.modifierDown(trigger)
            // Pressed while another modifier is physically held: a chord, not a tap.
            if let heldKeyCode = pressedModifierKeyCodes.first(where: { $0 != keyCode }) {
                oneShotState.keyDown(heldKeyCode)
            }
            return Unmanaged.passUnretained(event)
        }

        let pressEpoch = modifierEvidenceEpochs.removeValue(forKey: keyCode)
        let hasBinding = hasOneShotBinding(for: trigger)
        let output = oneShotState.modifierUp(
            trigger,
            hasDoubleTapBinding: hasDoubleTapBinding(for: trigger)
        )

        guard hasBinding else {
            return Unmanaged.passUnretained(event)
        }

        switch output {
        case .trigger(let output):
            let evidenceEpoch = output.gesture == .doubleTap && pendingTapEvidenceEpoch != pressEpoch ? nil : pressEpoch
            pendingTapEvidenceEpoch = nil
            pendingSingleTapTimer?.invalidate()
            pendingSingleTapTimer = nil
            if let binding = binding(for: output) {
                perform(binding.action, trigger: binding.trigger, evidenceEpoch: evidenceEpoch)
            }
        case .wait:
            if binding(for: trigger) != nil || hasDoubleTapBinding(for: trigger) {
                pendingTapEvidenceEpoch = pressEpoch
                scheduleSingleTapFlush()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !Self.isOwnSyntheticEvent(event) else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        oneShotState.keyDown(keyCode)
        guard !isCapturingShortcut else {
            // A repeat may belong to a key pressed before recording began.
            consumedKeyDowns.remove(keyCode)
            return Unmanaged.passUnretained(event)
        }
        guard let binding = keyPressBinding(forKeyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        perform(binding.action, trigger: binding.trigger, evidenceEpoch: triggerEvidenceEpoch)
        consumedKeyDowns.insert(keyCode)
        return nil
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !Self.isOwnSyntheticEvent(event) else {
            return Unmanaged.passUnretained(event)
        }
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
        pendingSingleTapTimer = Timer.scheduledTimer(withTimeInterval: OneShotModifierState.doubleTapWindow, repeats: false) { [weak self] _ in
            guard let self, !self.isCapturingShortcut else {
                return
            }
            if let trigger = self.oneShotState.flushPendingSingleTap(), let binding = self.binding(for: trigger) {
                self.perform(binding.action, trigger: binding.trigger, evidenceEpoch: self.pendingTapEvidenceEpoch)
            }
            self.pendingTapEvidenceEpoch = nil
            self.pendingSingleTapTimer = nil
        }
    }

    private func perform(_ action: BindingAction, trigger: KeyTrigger, evidenceEpoch: UUID?) {
        switch action.type {
        case .switchInputSource:
            guard let role = action.role else {
                return
            }
            requestSwitch(to: role, trigger: trigger, evidenceEpoch: evidenceEpoch)
        case .sendKey:
            guard let output = action.output else {
                return
            }
            postKey(output)
        case .disable:
            break
        }
    }

    /// Called from the event tap callback: only records the request and returns, so
    /// the callback never waits on TIS selection or confirmation retries.
    private func requestSwitch(to role: InputRole, trigger: KeyTrigger, evidenceEpoch: UUID?) {
        switchGeneration &+= 1
        let generation = switchGeneration
        Self.scheduleOnMainQueue(after: 0) { [weak self] in
            self?.beginSwitch(to: role, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
        }
    }

    private func isCurrentSwitch(_ generation: Int) -> Bool {
        generation == switchGeneration
    }

    private func beginSwitch(to role: InputRole, generation: Int, trigger: KeyTrigger, evidenceEpoch: UUID?) {
        guard isCurrentSwitch(generation) else {
            return
        }
        if resolvedSources[role] == nil {
            refreshResolvedSources()
        } else if resolvedSources[role]?.id != config.preference(for: role).preferredIDs.first {
            // A fallback is provisional: the preferred source may have appeared
            // since the last scan. Re-match only this slot; first-ID hits stay fast.
            do {
                let sources = try currentSources()
                resolvedSources[role] = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config)
            } catch {
                resolvedSources[role] = nil
                onMessage?("Input source refresh failed: \(error.localizedDescription)")
            }
        }
        guard let source = resolvedSources[role] else {
            onMessage?("No input method matched this switch slot.")
            return
        }
        // Only a live tap posts keys; a monitor that was never started has nothing to activate.
        // The strategy check comes first so unlisted input methods do no extra work, not even a TIS read.
        guard kanaKeyPoster != nil || isRunning,
              SwitchActivationPolicy.strategy(for: source, userRecipes: activationRecipes) == .kanaThenSelect,
              SwitchActivationPolicy.needsKanaPrelude(target: source, current: try? inputSources.currentInputSource(), userRecipes: activationRecipes) else {
            select(source, role: role, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
            return
        }
        (kanaKeyPoster ?? Self.postKanaKeyEvent)()
        let delay = SwitchActivationPolicy.kanaToSelectDelay(for: source, userRecipes: activationRecipes)
        Self.scheduleOnMainQueue(after: delay) { [weak self] in
            guard let self, self.isCurrentSwitch(generation) else {
                return
            }
            self.select(source, role: role, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
        }
    }

    private func select(_ source: InputSourceInfo, role: InputRole, generation: Int, trigger: KeyTrigger, evidenceEpoch: UUID?) {
        selectAndReport(source, role: role, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch, prefix: nil) { [weak self] originalError in
            guard let self else {
                return
            }
            self.refreshResolvedSources()
            guard let fallback = self.resolvedSources[role], fallback.id != source.id else {
                // No different source to fall back to; surface the real reason
                // instead of the generic "Action failed".
                self.onMessage?("Could not switch this slot: \(originalError.localizedDescription)")
                return
            }
            self.selectAndReport(
                fallback,
                role: role,
                generation: generation,
                trigger: trigger,
                evidenceEpoch: evidenceEpoch,
                prefix: "\(source.localizedName) failed: \(originalError.localizedDescription)"
            ) { [weak self] error in
                self?.onMessage?("Action failed: \(error.localizedDescription)")
            }
        }
    }

    /// Selects `source` and reports via `onSwitch` only once the selection is
    /// confirmed. Runs on the main thread; retries are scheduled, not slept.
    private func selectAndReport(
        _ source: InputSourceInfo,
        role: InputRole,
        generation: Int,
        trigger: KeyTrigger,
        evidenceEpoch: UUID?,
        prefix: String?,
        onError: @escaping (Error) -> Void
    ) {
        inputSources.selectInputSourceAndConfirm(
            id: source.id,
            retryDelays: eventTapConfirmationRetryDelays,
            schedule: Self.scheduleOnMainQueue,
            shouldContinue: { [weak self] in
                self?.isCurrentSwitch(generation) ?? false
            },
            completion: { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                case .success(let current):
                    self.report(current: current, requested: source, role: role, trigger: trigger, evidenceEpoch: evidenceEpoch, prefix: prefix)
                case .failure(let error):
                    onError(error)
                }
            }
        )
    }

    private func report(current: InputSourceInfo?, requested source: InputSourceInfo, role: InputRole, trigger: KeyTrigger, evidenceEpoch: UUID?, prefix: String?) {
        guard current?.id == source.id else {
            onMessage?(InputSourceInfo.verificationMessage(requested: source, current: current))
            return
        }
        onSwitch?(role, source)
        if !isCapturingShortcut, let evidenceEpoch, evidenceEpoch == triggerEvidenceEpoch {
            onTriggeredSwitch?(role, source, trigger)
        }
        if let prefix {
            onMessage?("\(prefix). Selected refreshed input method \(source.localizedName).")
        } else {
            onMessage?("Selected \(source.localizedName).")
        }
    }

    /// Marks the Kana key this monitor posts, so its own tap lets it through untouched.
    static let syntheticEventMarker: Int64 = 0x436D_6449_4D45

    static func isOwnSyntheticEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
    }

    /// The user's recipes from `ActivationRecipeStore`; they take precedence over the built-in ones.
    public var activationRecipes: [ActivationRecipe] = []

    /// Set by tests to observe the prelude without posting real events.
    var kanaKeyPoster: (() -> Void)?

    static func postKanaKeyEvent() {
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(SwitchActivationPolicy.kanaKeyCode), keyDown: isDown)
            event?.flags = []
            event?.setIntegerValueField(.eventSourceUserData, value: EventTapMonitor.syntheticEventMarker)
            event?.post(tap: .cghidEventTap)
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

    /// Updates `pressedModifierKeyCodes` for a `flagsChanged` event and returns true
    /// when it is a press. The aggregate flag (e.g. `.maskCommand`) stays set while
    /// either side is held, so it cannot tell a right-command release from a press
    /// while left-command is down; the per-keyCode set can. A cleared aggregate flag
    /// means every key of that family is up, which also resyncs after missed events.
    private func recordModifierTransition(keyCode: Int, flags: CGEventFlags) -> Bool {
        guard let flag = modifierFlag(forKeyCode: keyCode) else {
            return false
        }
        guard flags.contains(flag) else {
            pressedModifierKeyCodes = pressedModifierKeyCodes.filter { modifierFlag(forKeyCode: $0) != flag }
            return false
        }
        if pressedModifierKeyCodes.remove(keyCode) != nil {
            return false
        }
        pressedModifierKeyCodes.insert(keyCode)
        return true
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
