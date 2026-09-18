import AppKit
import Combine
import Carbon
import CoreGraphics
import KeyboardSwitcherCore

/// Owns capture for one presentation, independently of the popover's view lifetime.
@MainActor
final class TriggerRecordingSession: ObservableObject {
    enum EndReason {
        case explicitClose, disappeared, hostResigned, hostClosed, cancelled, committed
    }

    @Published private(set) var isRecording = false
    @Published private(set) var draft: KeyTrigger?
    @Published private(set) var heldKeys: [KeyTrigger] = []
    @Published private(set) var liveKeyNames: [String] = []
    @Published private(set) var warning: String?
    @Published private(set) var captureRevision = 0
    @Published private(set) var rejectionRevision = 0
    private(set) var sessionID = UUID()

    private weak var hostWindow: NSWindow?
    private var recognizer = TriggerRecognizer()
    private var initialOrdinaryKeys: Set<Int> = []
    private var resources = CaptureResources()
    private var onValidate: ((KeyTrigger) -> String?)?
    private var onCommit: ((KeyTrigger?) -> String?)?
    private var eligibility = TriggerRecordingDraftEligibility()
    private var onDismiss: (() -> Void)?
    private var warningBlocksSave = true

    init() {}

    var canSave: Bool { isRecording && eligibility.hasDraft && (warning == nil || !warningBlocksSave) }

    func cancel() { end(reason: .cancelled) }

    /// Mouse, accessibility and Return use the same path; host key status is not a precondition.
    func save() {
        guard isRecording else { return }
        guard eligibility.hasDraft else {
            if warning == nil, !eligibility.canClear, draft == nil {
                cancel()
            } else {
                reject("Record a trigger before saving.")
            }
            return
        }
        if let draft, let error = onValidate?(draft) {
            reject(error)
            return
        }
        guard warning == nil || !warningBlocksSave else { return }
        commit(draft)
    }

    func begin(
        in window: NSWindow,
        existingTrigger: KeyTrigger? = nil,
        onCaptureChanged: @escaping (Bool) -> Void,
        onValidate: @escaping (KeyTrigger) -> String?,
        onCommit: @escaping (KeyTrigger?) -> String?,
        onDismiss: @escaping () -> Void
    ) {
        // Never call an old (or newly installed) dismissal action while restarting.
        cleanup()
        sessionID = UUID()
        let generation = sessionID
        hostWindow = window
        self.onValidate = onValidate
        self.onCommit = onCommit
        eligibility = TriggerRecordingDraftEligibility(existingTrigger: existingTrigger)
        self.onDismiss = onDismiss
        let held = Set((0..<128).filter {
            $0 != kVK_CapsLock && $0 != kVK_Function
                && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
        })
        let heldModifiers = held.intersection(TriggerRecognizer.modifierTriggers.keys)
        initialOrdinaryKeys = held.subtracting(heldModifiers)
        recognizer = TriggerRecognizer(existingTrigger: existingTrigger,
                                       heldModifierKeyCodes: heldModifiers,
                                       heldKeyCodes: initialOrdinaryKeys)
        draft = recognizer.draft
        updateHeldKeys()
        liveKeyNames = draft.map(Self.components) ?? heldKeys.map(\.keyName)
        warning = nil
        resources.onCaptureChanged = onCaptureChanged
        isRecording = true
        resources.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isRecording, self.sessionID == generation else { return false }
                self.receive(event)
                return true
            }
            // Do not transfer NSEvent across actor boundaries, or let captured
            // Command chords reach menu equivalents.
            return consumed ? nil : event
        }
        let center = NotificationCenter.default
        resources.observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(reason: .hostResigned, sessionID: generation) }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(reason: .hostClosed, sessionID: generation) }
            },
        ]
        onCaptureChanged(true)
        announce("Recording. Press a trigger. Return saves; Escape cancels; Delete clears the draft.")
        if let draft, let error = onValidate(draft) { reject(error) }
    }

    func end(reason: EndReason, sessionID: UUID? = nil) {
        guard isRecording, sessionID == nil || sessionID == self.sessionID else { return }
        let dismiss = onDismiss
        switch reason {
        case .committed: announce("Trigger saved.")
        default: announce("Recording cancelled. Previous trigger unchanged.")
        }
        cleanup()
        dismiss?()
    }

    private func cleanup() {
        // Mark inactive before calling outward: disappearance can be reentrant.
        isRecording = false
        onValidate = nil
        onCommit = nil
        eligibility = TriggerRecordingDraftEligibility()
        onDismiss = nil
        hostWindow = nil
        recognizer = TriggerRecognizer()
        initialOrdinaryKeys = []
        draft = nil
        heldKeys = []
        liveKeyNames = []
        warning = nil
        resources.cleanup()
    }

    deinit {
        // ObservableObject owners normally die on the main actor; keep AppKit
        // teardown safe even if the final release comes from elsewhere.
        let resources = resources
        if Thread.isMainThread {
            MainActor.assumeIsolated { resources.cleanup() }
        } else {
            Task { @MainActor in resources.cleanup() }
        }
    }

    private func receive(_ event: NSEvent) {
        let code = Int(event.keyCode)
        let modifiers = Self.modifiers(event.modifierFlags)
        let name = Self.keyName(for: event) ?? ""
        let intent: TriggerRecognizer.Intent?
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            // Even an unsupported key poisons pending modifier taps. Its draft
            // is not published or committed; the physical down/up still routes.
            intent = recognizer.keyDown(keyCode: code, keyName: name,
                                        modifiers: modifiers, timestamp: event.timestamp)
        case .keyUp:
            initialOrdinaryKeys.remove(code)
            intent = recognizer.keyUp(keyCode: code, keyName: name,
                                      modifiers: modifiers, timestamp: event.timestamp)
        case .flagsChanged:
            // A key held before capture may have its release consumed upstream.
            // Reconcile only that initial set; never rewrite keys recorded here.
            initialOrdinaryKeys = Set(initialOrdinaryKeys.filter {
                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
            })
            recognizer.reconcileInitiallyHeldKeys(stillPressed: initialOrdinaryKeys)
            intent = recognizer.flagsChanged(keyCode: code, modifiers: modifiers,
                                             timestamp: event.timestamp)
        default:
            return
        }
        updateHeldKeys()
        if event.type == .keyUp || event.type == .flagsChanged {
            liveKeyNames = heldKeys.isEmpty
                ? (draft.map(Self.components) ?? [])
                : heldKeys.map(\.keyName)
        }
        guard let intent else {
            if event.type == .keyDown,
               TriggerRecognizer.modifierTriggers[code] == nil,
               modifiers.subtracting(Modifier.latching).isEmpty {
                if code == kVK_Delete || code == kVK_ForwardDelete {
                    // The core draft may already be nil after an earlier clear.
                    // Preserve the session's historical eligibility to clear.
                    if eligibility.canClear { clearDraft() }
                } else if code != kVK_Escape && code != kVK_Return && code != kVK_ANSI_KeypadEnter {
                    eligibility.reject()
                    reject("Use a modifier together with an ordinary key.")
                }
            }
            return
        }
        switch intent {
        case let .chord(trigger):
            captured(trigger)
        case .tap, .doubleTap:
            reject("This recorder only accepts keyboard shortcuts.")
        case .cancel:
            cancel()
        case .commit:
            save()
        case .clear:
            if eligibility.canClear { clearDraft() }
        }
    }

    private func clearDraft() {
        draft = nil
        liveKeyNames = []
        eligibility.clear()
        warning = nil
        captureRevision += 1
        announce("Trigger cleared. Press Return to save, or Escape to cancel.")
    }

    private func captured(_ trigger: KeyTrigger) {
        guard SlotTriggerCategory.shortcut.matches(trigger) else {
            reject("This recorder only accepts keyboard shortcuts.")
            return
        }
        guard !trigger.keyName.isEmpty else {
            eligibility.reject()
            reject("This key is not supported. Try another trigger.")
            return
        }
        draft = trigger
        if trigger.kind == .oneShotModifier {
            liveKeyNames = [trigger.keyName]
        } else {
            liveKeyNames = (heldKeys.isEmpty ? trigger.modifiers.map(\.rawValue) : heldKeys.map(\.keyName))
                + [trigger.keyName]
        }
        eligibility.capture()
        warning = nil
        captureRevision += 1
        if let error = onValidate?(trigger) {
            reject(error)
        } else {
            announce("Captured \(trigger.displayName). Press Return to save.")
        }
    }

    private static func components(_ trigger: KeyTrigger) -> [String] {
        trigger.kind == .oneShotModifier ? [trigger.keyName] : trigger.modifiers.map(\.rawValue) + [trigger.keyName]
    }

    private func updateHeldKeys() {
        heldKeys = recognizer.pressedModifierKeyCodes.sorted().compactMap {
            TriggerRecognizer.modifierTriggers[$0]
        }
    }

    private func commit(_ trigger: KeyTrigger?) {
        guard let onCommit else { return }
        let generation = sessionID
        let error = onCommit(trigger)
        guard isRecording, sessionID == generation else { return }
        if let error {
            reject(error, blocksSave: false)
        } else {
            end(reason: .committed, sessionID: generation)
        }
    }

    private func reject(_ message: String, blocksSave: Bool = true) {
        warningBlocksSave = blocksSave
        warning = message
        rejectionRevision += 1
        announce(message)
    }

    private func announce(_ message: String) {
        guard let hostWindow else { return }
        NSAccessibility.post(element: hostWindow, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<Modifier> {
        var result = Set<Modifier>()
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.function) { result.insert(.fn) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }

    // Derive special-key codes from the parser rather than maintaining another
    // hardware-code table. Ordinary characters supply names, never physical codes.
    private static let specialKeyNames: [Int: String] = {
        let names = ["return", "tab", "space", "delete", "escape", "left", "right", "up", "down"]
            + (1...20).map { "f\($0)" }
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            guard let trigger = try? ShortcutParser.parse(name) else { return nil }
            return (trigger.keyCode, trigger.keyName)
        })
    }()

    private static func keyName(for event: NSEvent) -> String? {
        if let name = specialKeyNames[Int(event.keyCode)] { return name }
        // AppKit's Unicode constants also cover keys not yet named by the parser.
        if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
            if scalar.value == UInt32(NSDeleteFunctionKey) { return "forward-delete" }
            if scalar.value == 0x03 { return "return" } // numeric keypad Enter
        }
        let unmodified = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let characters = unmodified?.lowercased(),
              characters.count == 1,
              let parsed = try? ShortcutParser.parse(characters),
              parsed.kind == .keyPress else { return nil }
        return parsed.keyName
    }
}

/// Pure session eligibility, independently testable without AppKit event delivery
/// or an NSWindow. Rejection blocks Return, but does not erase clear eligibility.
struct TriggerRecordingDraftEligibility: Equatable {
    private(set) var hasDraft: Bool
    private(set) var canClear: Bool

    init(existingTrigger: KeyTrigger? = nil) {
        hasDraft = existingTrigger != nil
        canClear = existingTrigger != nil
    }

    mutating func capture() {
        hasDraft = true
        canClear = true
    }

    mutating func clear() {
        hasDraft = true
        canClear = true
    }

    mutating func reject() {
        hasDraft = false
    }
}

/// Only accessed on the main actor. Sendability permits scheduling final cleanup
/// from a nonisolated deinitializer without transferring the recording session.
private final class CaptureResources: @unchecked Sendable {
    var monitor: Any?
    var observers: [NSObjectProtocol] = []
    var onCaptureChanged: ((Bool) -> Void)?

    @MainActor func cleanup() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        let callback = onCaptureChanged
        onCaptureChanged = nil
        callback?(false)
    }
}
