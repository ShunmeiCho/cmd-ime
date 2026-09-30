import AppKit
import KeyboardSwitcherCore

/// Decides when the switch indicator appears beyond the moment a trigger switches: a change
/// made outside CmdIME, and an app switch that leaves a different source. The decisions live in
/// `IndicatorOccasionTracker`; this class feeds it events and hands a source to draw back to
/// the app model, which owns the bubble.
@MainActor
final class IndicatorOccasionController {
    private let inputSources: InputSourceService
    private let config: () -> SwitcherConfig
    private let isOwnSwitchPending: () -> Bool
    private let present: (InputSourceInfo) -> Void
    private var tracker: IndicatorOccasionTracker
    private var activationObserver: NSObjectProtocol?
    private var settleTask: Task<Void, Never>?

    init(
        inputSources: InputSourceService,
        config: @escaping () -> SwitcherConfig,
        isOwnSwitchPending: @escaping () -> Bool,
        present: @escaping (InputSourceInfo) -> Void
    ) {
        self.inputSources = inputSources
        self.config = config
        self.isOwnSwitchPending = isOwnSwitchPending
        self.present = present
        tracker = IndicatorOccasionTracker(currentSourceID: (try? inputSources.currentInputSource())?.id)
    }

    /// Follows app activations only while app-switch bubbles can show.
    func update() {
        let current = config()
        let wantsActivations = current.showSwitchIndicator && current.switchIndicatorBehavior.showsOnAppSwitch
        if wantsActivations, activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.appDidActivate(app) }
            }
        } else if !wantsActivations, let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
            settleTask?.cancel()
            settleTask = nil
        }
    }

    /// CmdIME confirmed a switch it made. Returns whether its bubble may show.
    func ownSwitchConfirmed(sourceID: String, reported: Bool) -> Bool {
        tracker.ownSwitchConfirmed(
            sourceID: sourceID,
            reported: reported,
            frontmostAppID: Self.frontmostAppID,
            config: config()
        )
    }

    /// The selected input source changed, by any route.
    func sourceDidChange() {
        let current = try? inputSources.currentInputSource()
        let shows = tracker.sourceChanged(
            to: current?.id,
            isOwnSwitchPending: isOwnSwitchPending(),
            frontmostAppID: Self.frontmostAppID,
            config: config()
        )
        if shows, let current { present(current) }
    }

    private func appDidActivate(_ app: NSRunningApplication?) {
        guard let appID = app?.cmdIMEAppID else { return }
        tracker.appActivated(appID)
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(IndicatorOccasionTracker.appSwitchSettleDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.appSwitchDidSettle(appID)
        }
    }

    private func appSwitchDidSettle(_ appID: String) {
        let current = try? inputSources.currentInputSource()
        let shows = tracker.appSwitchSettled(appID: appID, currentSourceID: current?.id, config: config())
        if shows, let current { present(current) }
    }

    private static var frontmostAppID: String? {
        NSWorkspace.shared.frontmostApplication?.cmdIMEAppID
    }
}

extension NSRunningApplication {
    /// Bundle id, or the executable path for an app without one: the key App Memory and the
    /// indicator's hidden-app list use.
    var cmdIMEAppID: String? {
        bundleIdentifier ?? executableURL?.path
    }
}
