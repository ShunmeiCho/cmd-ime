import AppKit
import Carbon
import KeyboardSwitcherCore

/// Follows which app is in front and drives App Memory and App Rules (CONTEXT.md): remembers the
/// input source last used in each app, selects what a rule, the memory or the default slot asks
/// for when an app comes back, and puts back the source a password field replaced. The decisions
/// live in `AppMemoryTracker`; this class only observes, reads the current state and asks the
/// monitor to switch, so a restore obeys the same supersession and Kana rules as a trigger.
@MainActor
final class AppMemoryController {
    private let inputSources: InputSourceService
    private let monitor: () -> EventTapMonitor?
    private let sources: () -> [InputSourceInfo]
    private let slotForSourceID: (String) -> InputRole?
    private let sourceForSlot: (InputRole) -> InputSourceInfo?
    private var settings = AppActivationSettings()
    private var tracker = AppMemoryTracker(ownAppID: AppMemoryController.ownAppID)
    private var activationObserver: NSObjectProtocol?
    private var secureInputEndPoll: Timer?
    private var publishedMemory: [String: String] = [:]

    private(set) var isActive = false
    /// App id to remembered source id, every time that changes.
    var onMemoryChange: (([String: String]) -> Void)?

    init(
        inputSources: InputSourceService,
        monitor: @escaping () -> EventTapMonitor?,
        sources: @escaping () -> [InputSourceInfo],
        slotForSourceID: @escaping (String) -> InputRole?,
        sourceForSlot: @escaping (InputRole) -> InputSourceInfo?
    ) {
        self.inputSources = inputSources
        self.monitor = monitor
        self.sources = sources
        self.slotForSourceID = slotForSourceID
        self.sourceForSlot = sourceForSlot
    }

    /// Follows apps only while some per-app setting is on and the listener runs: paused means
    /// CmdIME leaves input sources alone. Stopping forgets everything.
    func update(settings: AppActivationSettings, isListening: Bool) {
        self.settings = settings
        let shouldRun = isListening && settings.isAnythingOn
        if shouldRun, isActive {
            tracker.update(settings: settings)
            publishMemory()
        } else if shouldRun {
            start()
        } else if isActive {
            stop()
        }
    }

    /// The selected input source changed, by any route.
    func sourceDidChange() {
        guard isActive, isPermitted, let current = currentSourceID() else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        tracker.sourceChanged(to: current, context: context(frontmostPID: frontmost))
        afterTrackerChange()
    }

    /// The monitor confirmed a switch it made (a trigger or a restore).
    func switchDidConfirm(sourceID: String) {
        guard isActive else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        tracker.switchConfirmed(sourceID: sourceID, context: context(frontmostPID: frontmost))
        afterTrackerChange()
    }

    func forget(appID: String) {
        tracker.forget(appID)
        publishMemory()
    }

    func forgetAll() {
        tracker.forgetAll()
        afterTrackerChange()
    }

    private func start() {
        tracker = AppMemoryTracker(
            ownAppID: Self.ownAppID,
            frontmostAppID: Self.trackedAppID(of: NSWorkspace.shared.frontmostApplication),
            settings: settings
        )
        // Only activations are observed, never terminations: an app that quits and comes back
        // keeps its memory, because apps are keyed by bundle id or path, not by process.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appDidActivate(app) }
        }
        isActive = true
        sourceDidChange()
    }

    private func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        tracker.forgetAll()
        isActive = false
        afterTrackerChange()
    }

    private func appDidActivate(_ app: NSRunningApplication?) {
        guard isActive, isPermitted, let app, let appID = Self.appID(of: app) else { return }
        let restore = tracker.appActivated(
            appID,
            isRegularApp: app.activationPolicy == .regular,
            currentSourceID: currentSourceID(),
            context: context(frontmostPID: app.processIdentifier),
            slotOfSource: slotForSourceID
        )
        afterTrackerChange()
        perform(restore)
    }

    private func perform(_ restore: AppMemoryTracker.Restore) {
        guard let monitor = monitor() else { return }
        switch restore {
        case .none:
            return
        case .select(let sourceID):
            // A source uninstalled since it was remembered is skipped, not an error.
            guard let source = selectableSource(sourceID) else { return }
            monitor.requestSwitch(to: source, reportingAs: slotForSourceID(source.id))
        case .selectSlot(let slot):
            // Resolved here so the switch is a source switch the tracker can put back if the
            // app is left before it lands; a slot with no matching source is skipped.
            guard let source = sourceForSlot(slot) else { return }
            monitor.requestSwitch(to: source, reportingAs: slot)
        case .putBack(let sourceID):
            guard let source = selectableSource(sourceID) else { return }
            monitor.requestSwitch(to: source, reportingAs: nil)
        }
    }

    private func afterTrackerChange() {
        publishMemory()
        watchSecureInputEnd()
    }

    private func publishMemory() {
        let memory = isActive ? tracker.rememberedSources : [:]
        guard memory != publishedMemory else { return }
        publishedMemory = memory
        onMemoryChange?(memory)
    }

    /// macOS posts nothing when secure input ends, and leaving a password field does not change
    /// the source back, so the end is polled for, only while a replaced source waits to return.
    private func watchSecureInputEnd() {
        guard isActive, tracker.isAwaitingSecureInputEnd else {
            secureInputEndPoll?.invalidate()
            secureInputEndPoll = nil
            return
        }
        guard secureInputEndPoll == nil else { return }
        secureInputEndPoll = Timer.scheduledTimer(withTimeInterval: Self.secureInputPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSecureInputEnded() }
        }
    }

    private func checkSecureInputEnded() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard !Self.isSecureInputHeld(byPID: frontmost?.processIdentifier) else { return }
        secureInputEndPoll?.invalidate()
        secureInputEndPoll = nil
        guard isActive, isPermitted, Self.appID(of: frontmost) == tracker.frontmostAppID else {
            _ = tracker.secureInputEnded(currentSourceID: nil, context: AppMemoryContext())
            return
        }
        let restore = tracker.secureInputEnded(
            currentSourceID: currentSourceID(),
            context: context(frontmostPID: frontmost?.processIdentifier)
        )
        perform(restore)
    }

    private static let secureInputPollInterval: TimeInterval = 0.25

    private func selectableSource(_ id: String) -> InputSourceInfo? {
        InputSourceMatcher.selectableSources(from: sources()).first { $0.id == id }
    }

    private func context(frontmostPID: pid_t?) -> AppMemoryContext {
        let monitor = monitor()
        return AppMemoryContext(
            isOwnSwitchPending: monitor?.isSwitchPending ?? false,
            isRestorePending: monitor?.isSourceSwitchPending ?? false,
            isSecureInputInFrontmostApp: Self.isSecureInputHeld(byPID: frontmostPID)
        )
    }

    /// Permissions can be revoked while the listener object still exists; nothing is recorded
    /// or restored once they are gone. Accessibility is cheap to read on every event; the Input
    /// Monitoring preflight costs a round trip to tccd, so it is re-read at most once a second,
    /// which bursts of notifications (a Kana prelude, a Cmd-Tab) would otherwise repeat.
    private var isPermitted: Bool {
        guard AXIsProcessTrusted() else { return false }
        let now = Date()
        if let checked = inputMonitoringCheck, now.timeIntervalSince(checked.at) < Self.inputMonitoringRecheckInterval {
            return checked.granted
        }
        let granted = CGPreflightListenEventAccess()
        inputMonitoringCheck = (granted, now)
        return granted
    }
    private var inputMonitoringCheck: (granted: Bool, at: Date)?
    private static let inputMonitoringRecheckInterval: TimeInterval = 1

    private func currentSourceID() -> String? {
        (try? inputSources.currentInputSource())?.id
    }

    /// Secure input is system-wide, so only the app the system names as its holder counts. That
    /// name is the app that was in front when secure input was turned on, not the process that
    /// turned it on: a background holder is charged to that one app, and App Memory stays off for
    /// it until secure input ends. When the holder cannot be read, assume the app in front, so
    /// nothing forced gets remembered.
    private static func isSecureInputHeld(byPID pid: pid_t?) -> Bool {
        guard IsSecureEventInputEnabled() else { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let holder = session["kCGSSessionSecureInputPID"] as? Int else {
            return true
        }
        return pid.map { Int($0) == holder } ?? true
    }

    private static let ownAppID = appID(of: .current)

    /// Bundle id, or the executable path for an app without one.
    private static func appID(of app: NSRunningApplication?) -> String? {
        app?.bundleIdentifier ?? app?.executableURL?.path
    }

    /// The app in front when following starts, if it is one the tracker follows (see
    /// `AppMemoryTracker.appActivated`): a regular app, or CmdIME.
    private static func trackedAppID(of app: NSRunningApplication?) -> String? {
        guard let app, let id = appID(of: app) else { return nil }
        return app.activationPolicy == .regular || id == ownAppID ? id : nil
    }
}
