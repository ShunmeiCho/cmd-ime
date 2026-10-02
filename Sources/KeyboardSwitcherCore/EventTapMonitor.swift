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
    /// A confirmed switch with no slot to report (`requestSwitch(to:reportingAs: nil)`), so
    /// the app still knows the change was its own.
    public var onSilentSwitch: ((InputSourceInfo) -> Void)?
    /// A peek binding fired. Called on the main queue, after the tap callback has returned.
    public var onPeek: (() -> Void)?
    /// Auto space (issue #10): reads the one character before the caret. Called off the main thread,
    /// never from the tap callback. Nil (the CLI, tests that do not set it) leaves auto space off.
    public var characterBeforeCaret: (@Sendable () -> String?)?
    /// Caps Lock turned on (true) or off. Called on the main queue, after the tap callback has returned.
    public var onCapsLockChange: ((Bool) -> Void)?

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
                pendingSwitchDeadline = nil
            }
        }
    }
    private var capturingShortcut = false

    private let inputSources: InputSourceService
    private let addGlobalMouseDownMonitor: GlobalMouseDownMonitorInstaller
    private let addLocalMouseDownMonitor: LocalMouseDownMonitorInstaller
    private let removeMouseDownMonitor: MouseDownMonitorRemover
    /// Monotonic seconds; how long a one-shot modifier was held is measured with it.
    private let now: () -> TimeInterval
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseDownMonitors: [Any] = []
    private var oneShotState = OneShotModifierState()
    private var capsLock = CapsLockTracker()
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
    /// When the last posted Kana key has had time to take effect.
    private var kanaSettlesAt = Date.distantPast
    /// Set while the current switch is neither confirmed nor abandoned. The deadline covers the
    /// longest Kana delay plus the confirmation retry, so a switch that never reports cannot
    /// leave the flag set.
    private var pendingSwitchDeadline: Date?
    static let pendingSwitchBudget: TimeInterval = 1.0

    /// True while a switch this monitor started is still in flight. Input-source changes seen
    /// meanwhile are its own intermediate steps (a Kana prelude, a retry), not the user's.
    public var isSwitchPending: Bool {
        precondition(Thread.isMainThread)
        return (pendingSwitchDeadline?.timeIntervalSinceNow ?? 0) > 0
    }

    /// True while the switch in flight is one of `requestSwitch(to:reportingAs:)`, never a
    /// trigger: only such a switch may be put back when the app it was meant for is left.
    public var isSourceSwitchPending: Bool {
        isSwitchPending && pendingTargetIsSource
    }
    private var pendingTargetIsSource = false

    /// What a switch aims at: a slot resolved through the matcher, or one concrete source
    /// (App Memory restores a source the user had, which may belong to no slot).
    private enum SwitchTarget {
        case slot(InputRole)
        case source(InputSourceInfo, reportingAs: InputRole?)
        /// A Toggle: becomes `.slot` on the main queue, once the source in front can be read.
        case toggle(InputRole, InputRole)

        var role: InputRole? {
            switch self {
            case .slot(let role): role
            case .source(_, let role): role
            case .toggle: nil
            }
        }
    }

    public static func scheduleOnMainQueue(after delay: TimeInterval, _ work: @escaping () -> Void) {
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

    /// Events that cancel a pending one-shot modifier: a click, or a scroll (Command-scroll
    /// zooms, and releasing Command afterwards must not switch).
    static let oneShotCancelEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .scrollWheel,
    ]

    /// Scroll momentum keeps arriving after the fingers lift, and a touch that does not move
    /// posts zero-delta phase events; only a scroll the user is making cancels a tap.
    static func cancelsOneShot(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel else {
            return true
        }
        return event.momentumPhase.isEmpty && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0)
    }

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
        removeMouseDownMonitor: @escaping MouseDownMonitorRemover,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.config = config
        self.inputSources = inputSources
        self.addGlobalMouseDownMonitor = addGlobalMouseDownMonitor
        self.addLocalMouseDownMonitor = addLocalMouseDownMonitor
        self.removeMouseDownMonitor = removeMouseDownMonitor
        self.now = now
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
        capsLock = CapsLockTracker(isOn: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift))

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
        onMessage?(CoreLocalization.text("Listener started."))
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
        pendingSwitchDeadline = nil
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

    /// Slots this monitor confirmed a switch to, most recent first; a Toggle reads it.
    private(set) var recentSlots: [InputRole] = []

    private(set) var autoSpace = AutoSpaceState()

    /// Set by tests to observe the space and the re-posted key without posting real events.
    var autoSpaceKeyPoster: ((CGEvent) -> Void)?

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
            onMessage?(CoreLocalization.text("Input source refresh failed: %@", String(describing: error.localizedDescription)))
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

        if let globalMonitor = addGlobalMouseDownMonitor(Self.oneShotCancelEventMask, { [weak self] event in
            guard Self.cancelsOneShot(event) else { return }
            self?.cancelOneShotFromMouseDown(clicked: event.type != .scrollWheel)
        }) {
            mouseDownMonitors.append(globalMonitor)
        }
        if let localMonitor = addLocalMouseDownMonitor(Self.oneShotCancelEventMask, { [weak self] event in
            if Self.cancelsOneShot(event) {
                self?.cancelOneShotFromMouseDown(clicked: event.type != .scrollWheel)
            }
            return event
        }) {
            mouseDownMonitors.append(localMonitor)
        }
    }

    private func cancelOneShotFromMouseDown(clicked: Bool) {
        if Thread.isMainThread {
            oneShotState.cancel()
            // A click can move the caret, so the character read before it says nothing about where
            // the next key lands. A scroll does not move it.
            if clicked { autoSpace.cancel() }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.oneShotState.cancel()
                if clicked { self?.autoSpace.cancel() }
            }
        }
    }

    /// An app switch or a focus change: the caret the read looked at is no longer where keys go.
    public func cancelAutoSpace() {
        autoSpace.cancel()
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

    /// True until the single-tap flush timer has fired or been cancelled.
    var hasPendingSingleTapForTesting: Bool {
        pendingSingleTapTimer?.isValid ?? false
    }

    /// Seconds until the pending single-tap flush timer stops waiting for a second tap.
    var pendingSingleTapRemainingForTesting: TimeInterval? {
        pendingSingleTapTimer.map { $0.fireDate.timeIntervalSinceNow }
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
        if keyCode == kVK_CapsLock {
            reportCapsLockChange(flags: event.flags)
        }
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
            oneShotState.modifierDown(trigger, at: now())
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
            hasDoubleTapBinding: hasDoubleTapBinding(for: trigger),
            at: now()
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
            let hasSingleTapBinding = binding(for: trigger) != nil
            if hasSingleTapBinding || hasDoubleTapBinding(for: trigger) {
                pendingTapEvidenceEpoch = pressEpoch
                scheduleSingleTapFlush(
                    after: OneShotModifierState.secondTapWindow(hasSingleTapBinding: hasSingleTapBinding)
                )
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
        if autoSpace.phase != .idle, spaceBefore(event) {
            return nil
        }
        guard let binding = keyPressBinding(forKeyCode: keyCode, flags: event.flags) else {
            // A repeat of a consumed press stays consumed though the modifiers changed since (the
            // other side was added): its key-up is swallowed, so letting the repeat through would
            // hand the app a key that never comes up.
            if consumedKeyDowns.contains(keyCode), event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return nil
            }
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
        var bestMatch: KeyBinding?
        for binding in config.bindings where binding.enabled && binding.trigger.kind == .keyPress && binding.trigger.keyCode == keyCode {
            guard eventFlags(flags, contain: binding.trigger.modifiers, modifierSides: binding.trigger.modifierSides) else {
                continue
            }
            if binding.trigger.modifierSides.count > (bestMatch?.trigger.modifierSides.count ?? -1) {
                bestMatch = binding
            }
        }
        return bestMatch
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

    private func scheduleSingleTapFlush(after window: TimeInterval) {
        pendingSingleTapTimer?.invalidate()
        pendingSingleTapTimer = Timer.scheduledTimer(withTimeInterval: window, repeats: false) { [weak self] _ in
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
        case .showIndicator:
            Self.scheduleOnMainQueue(after: 0) { [weak self] in
                self?.onPeek?()
            }
        case .toggleSlots:
            guard let roles = action.roles, roles.count == 2 else {
                return
            }
            request(.toggle(roles[0], roles[1]), trigger: trigger, evidenceEpoch: evidenceEpoch)
        }
    }

    /// Only the Caps Lock key's own events are read: a posted modifier event (the lab's, another
    /// app's) can carry flags without the lock bit and would announce a toggle that never happened.
    private func reportCapsLockChange(flags: CGEventFlags) {
        guard let isOn = capsLock.observe(isOn: flags.contains(.maskAlphaShift)) else { return }
        Self.scheduleOnMainQueue(after: 0) { [weak self] in
            self?.onCapsLockChange?(isOn)
        }
    }

    /// Called from the event tap callback: only records the request and returns, so
    /// the callback never waits on TIS selection or confirmation retries.
    private func requestSwitch(to role: InputRole, trigger: KeyTrigger, evidenceEpoch: UUID?) {
        request(.slot(role), trigger: trigger, evidenceEpoch: evidenceEpoch)
    }

    /// Selects one concrete source through the same path as a trigger: a newer switch or
    /// trigger supersedes it, the Kana prelude applies, and only a confirmed selection reports.
    /// `role` is the slot `onSwitch` reports, if the source belongs to one; without it the
    /// switch is silent. Call on the main thread.
    public func requestSwitch(to source: InputSourceInfo, reportingAs role: InputRole?) {
        precondition(Thread.isMainThread)
        request(.source(source, reportingAs: role), trigger: nil, evidenceEpoch: nil)
    }

    private func request(_ target: SwitchTarget, trigger: KeyTrigger?, evidenceEpoch: UUID?) {
        switchGeneration &+= 1
        let generation = switchGeneration
        pendingSwitchDeadline = Date(timeIntervalSinceNow: Self.pendingSwitchBudget)
        if case .source = target {
            pendingTargetIsSource = true
        } else {
            pendingTargetIsSource = false
        }
        Self.scheduleOnMainQueue(after: 0) { [weak self] in
            self?.beginSwitch(to: target, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
        }
    }

    private func isCurrentSwitch(_ generation: Int) -> Bool {
        generation == switchGeneration
    }

    /// The current switch ended, confirmed or not. A superseded one leaves the flag to its successor.
    private func endSwitch(_ generation: Int) {
        if isCurrentSwitch(generation) {
            pendingSwitchDeadline = nil
        }
    }

    private func beginSwitch(to requested: SwitchTarget, generation: Int, trigger: KeyTrigger?, evidenceEpoch: UUID?) {
        guard isCurrentSwitch(generation) else {
            return
        }
        let target = decidingToggle(requested)
        guard let source = resolvedSource(for: target) else {
            onMessage?(CoreLocalization.text("No input method matched this switch slot."))
            endSwitch(generation)
            return
        }
        // Only a live tap posts keys; a monitor that was never started has nothing to activate.
        // The strategy check comes first so unlisted input methods do no extra work, not even a TIS read.
        guard kanaKeyPoster != nil || isRunning,
              SwitchActivationPolicy.strategy(for: source, userRecipes: activationRecipes) == .kanaThenSelect,
              SwitchActivationPolicy.needsKanaPrelude(target: source, current: try? inputSources.currentInputSource(), userRecipes: activationRecipes) else {
            // A Kana key from a switch this one superseded may still be taking effect; selecting
            // before it lands would let the system's Kana switch override this one.
            let wait = kanaSettlesAt.timeIntervalSinceNow
            guard wait > 0 else {
                select(source, target: target, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
                return
            }
            Self.scheduleOnMainQueue(after: wait) { [weak self] in
                guard let self, self.isCurrentSwitch(generation) else {
                    return
                }
                self.select(source, target: target, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
            }
            return
        }
        (kanaKeyPoster ?? Self.postKanaKeyEvent)()
        let delay = SwitchActivationPolicy.kanaToSelectDelay(for: source, userRecipes: activationRecipes)
        kanaSettlesAt = Date(timeIntervalSinceNow: delay)
        Self.scheduleOnMainQueue(after: delay) { [weak self] in
            guard let self, self.isCurrentSwitch(generation) else {
                return
            }
            self.select(source, target: target, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch)
        }
    }

    /// A Toggle goes to the other slot when the source in front belongs to one of its two, else to
    /// the one switched to last. "Belongs to" is the matcher Peek uses, over every slot in order, so a
    /// source an earlier slot falls back to counts as that slot's, not as one of the Toggle's.
    private func decidingToggle(_ target: SwitchTarget) -> SwitchTarget {
        guard case let .toggle(first, second) = target else {
            return target
        }
        let currentID = (try? inputSources.currentInputSource())?.id
        let current = (try? currentSources()).flatMap {
            InputSourceMatcher.slotID(forSelectedSourceID: currentID, sources: $0, config: config)
        }
        return .slot(ToggleDecision.target(first: first, second: second, current: current, recentSlots: recentSlots))
    }

    private func resolvedSource(for target: SwitchTarget) -> InputSourceInfo? {
        let role: InputRole
        switch target {
        case .source(let source, _):
            return source
        case .slot(let slot):
            role = slot
        case .toggle:
            return nil
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
                onMessage?(CoreLocalization.text("Input source refresh failed: %@", String(describing: error.localizedDescription)))
            }
        }
        return resolvedSources[role]
    }

    private func select(_ source: InputSourceInfo, target: SwitchTarget, generation: Int, trigger: KeyTrigger?, evidenceEpoch: UUID?) {
        let role = target.role
        selectAndReport(source, role: role, generation: generation, trigger: trigger, evidenceEpoch: evidenceEpoch, prefix: nil) { [weak self] originalError in
            guard let self else {
                return
            }
            // Only a slot can fall back; a concrete source either selects or it does not.
            guard case .slot(let slot) = target else {
                self.onMessage?(CoreLocalization.text("Could not select %@: %@", String(describing: source.localizedName), String(describing: originalError.localizedDescription)))
                self.endSwitch(generation)
                return
            }
            self.refreshResolvedSources()
            guard let fallback = self.resolvedSources[slot], fallback.id != source.id else {
                // No different source to fall back to; surface the real reason
                // instead of the generic "Action failed".
                self.onMessage?(CoreLocalization.text("Could not switch this slot: %@", String(describing: originalError.localizedDescription)))
                self.endSwitch(generation)
                return
            }
            self.selectAndReport(
                fallback,
                role: slot,
                generation: generation,
                trigger: trigger,
                evidenceEpoch: evidenceEpoch,
                prefix: CoreLocalization.text("%@ failed: %@", String(describing: source.localizedName), String(describing: originalError.localizedDescription))
            ) { [weak self] error in
                self?.onMessage?(CoreLocalization.text("Action failed: %@", String(describing: error.localizedDescription)))
                self?.endSwitch(generation)
            }
        }
    }

    /// Selects `source` and reports via `onSwitch` only once the selection is
    /// confirmed. Runs on the main thread; retries are scheduled, not slept.
    private func selectAndReport(
        _ source: InputSourceInfo,
        role: InputRole?,
        generation: Int,
        trigger: KeyTrigger?,
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
                    self.endSwitch(generation)
                case .failure(let error):
                    onError(error)
                }
            }
        )
    }

    private func report(current: InputSourceInfo?, requested source: InputSourceInfo, role: InputRole?, trigger: KeyTrigger?, evidenceEpoch: UUID?, prefix: String?) {
        guard current?.id == source.id else {
            onMessage?(InputSourceInfo.verificationMessage(requested: source, current: current))
            return
        }
        if let role {
            recentSlots.removeAll { $0 == role }
            recentSlots.insert(role, at: 0)
            onSwitch?(role, source)
            if !isCapturingShortcut, let trigger, let evidenceEpoch, evidenceEpoch == triggerEvidenceEpoch {
                onTriggeredSwitch?(role, source, trigger)
                armAutoSpace(switchingTo: source)
            } else {
                autoSpace.cancel()
            }
        } else {
            autoSpace.cancel()
            onSilentSwitch?(source)
        }
        if let prefix {
            onMessage?(CoreLocalization.text("%@. Selected refreshed input method %@.", String(describing: prefix), String(describing: source.localizedName)))
        } else {
            onMessage?(CoreLocalization.text("Selected %@.", String(describing: source.localizedName)))
        }
    }

    /// A trigger switch into a Latin source: read the character before the caret off the main thread and
    /// keep only whether the next key needs a space. The tap never waits on the read.
    private func armAutoSpace(switchingTo source: InputSourceInfo) {
        guard config.autoSpaceAfterHan, let reader = characterBeforeCaret, AutoSpace.arms(switchingTo: source) else {
            autoSpace.cancel()
            return
        }
        let generation = autoSpace.armed()
        let monitor = WeakMonitor(self)
        DispatchQueue.global(qos: .userInitiated).async {
            let before = AutoSpace.classify(reader())
            Self.scheduleOnMainQueue(after: 0) {
                monitor.value?.autoSpace.read(before, generation: generation)
            }
        }
    }

    /// Called from the tap callback. When the key gets a space, posts the space and the key again (both
    /// marked, so the tap lets them through) and the caller swallows the original, keeping their order.
    private func spaceBefore(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let held = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard autoSpace.keyDown(characters: Self.characters(of: event), commandControlOrOption: held || isRepeat),
              let key = event.copy() else {
            return false
        }
        let post = autoSpaceKeyPoster ?? { $0.post(tap: .cghidEventTap) }
        for isDown in [true, false] {
            guard let space = CGEvent(keyboardEventSource: nil, virtualKey: Self.spaceKeyCode, keyDown: isDown) else { continue }
            space.flags = []
            space.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            post(space)
        }
        key.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        post(key)
        return true
    }

    private static let spaceKeyCode: CGKeyCode = 49
    private static let maxKeyCharacters = 4

    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: maxKeyCharacters)
        event.keyboardGetUnicodeString(maxStringLength: maxKeyCharacters, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    /// Lets the read's completion find the monitor without keeping it alive.
    private final class WeakMonitor: @unchecked Sendable {
        weak var value: EventTapMonitor?
        init(_ value: EventTapMonitor) { self.value = value }
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

    public static func postKanaKeyEvent() {
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

        let flags = outputFlags(for: trigger)
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

    // Device-dependent NX_DEVICE*KEYMASK values from IOLLEvent.h.
    private enum DeviceModifierMasks {
        static let leftControl: UInt64 = 0x1
        static let leftShift: UInt64 = 0x2
        static let rightShift: UInt64 = 0x4
        static let leftCommand: UInt64 = 0x8
        static let rightCommand: UInt64 = 0x10
        static let leftOption: UInt64 = 0x20
        static let rightOption: UInt64 = 0x40
        static let rightControl: UInt64 = 0x2000

        static let pairs: [Modifier: (left: UInt64, right: UInt64)] = [
            .command: (leftCommand, rightCommand),
            .option: (leftOption, rightOption),
            .control: (leftControl, rightControl),
            .shift: (leftShift, rightShift),
        ]
    }

    func eventFlags(_ flags: CGEventFlags, contain modifiers: [Modifier], modifierSides: [Modifier: ModifierSide] = [:]) -> Bool {
        let expected = Set(modifiers)
        let actual = Set(Modifier.allCases.filter { flags.contains(cgFlag(for: $0)) })
            .subtracting(Modifier.latching.subtracting(expected))
        guard actual == expected else { return false }
        return modifierSides.allSatisfy { modifier, side in
            guard let masks = DeviceModifierMasks.pairs[modifier] else { return false }
            let pressed = flags.rawValue & (masks.left | masks.right)
            // Synthesized events may omit both device bits; keep aggregate matching then.
            return pressed == 0 || pressed == (side == .left ? masks.left : masks.right)
        }
    }

    /// The flags of a posted key: a sided modifier carries its device bit, so the output reads as
    /// that side to whoever receives it.
    func outputFlags(for trigger: KeyTrigger) -> CGEventFlags {
        let deviceBits = trigger.modifierSides.reduce(UInt64(0)) { bits, entry in
            guard let masks = DeviceModifierMasks.pairs[entry.key] else { return bits }
            return bits | (entry.value == .left ? masks.left : masks.right)
        }
        return CGEventFlags(rawValue: cgFlags(from: trigger.modifiers).rawValue | deviceBits)
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
            CoreLocalization.text("Accessibility and Input Monitoring permissions are required before keyboard control can start.")
        case .failedToCreateEventTap:
            CoreLocalization.text("Failed to create keyboard event tap. Grant Accessibility and Input Monitoring permissions, then retry.")
        }
    }
}
#endif
