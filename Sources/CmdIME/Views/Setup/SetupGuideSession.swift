import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Session-only state of the setup guide. Nothing here is persisted; the only stored
/// fact is `SwitcherConfig.hasCompletedSetup`.
struct SetupGuideSession: Equatable {
    /// The user pressed "Looks right" in the review step.
    var hasConfirmedSlots = false
    /// A returning user reopened the guide from General > Setup guide.
    var isReopened = false
    /// Slots fired at least once during "Try it".
    var triedSlots: Set<InputRole> = []
    /// Sections unfolded by hand, or by "Change", while the first-run guide is open.
    var unfoldedSections: Set<SetupFoldSection> = []
}

extension AppModel {
    /// The guide state derived from live model state. A reopened guide walks the
    /// steps again without touching the stored `hasCompletedSetup`.
    func setupGuideState(session: SetupGuideSession) -> SetupGuideState {
        var input = SetupGuideInput(
            config: config,
            sources: sources,
            accessibilityGranted: permissions.accessibilityGranted,
            inputMonitoringGranted: permissions.inputMonitoringGranted,
            listenerFailed: didListenerFailToStart,
            hasConfirmedSlots: session.hasConfirmedSlots
        )
        if session.isReopened {
            input.hasCompletedSetup = false
        }
        return SetupGuideState(input)
    }

    /// Finish or Skip. The guide closes for this session even when the save fails,
    /// so the window can never get stuck behind it; `statusText` carries the error.
    func completeSetup() {
        guard !config.hasCompletedSetup else { return }
        config = config.completingSetup()
        save()
    }
}

@MainActor
enum SetupGuideNavigation {
    /// The id of the guide card inside the settings scroll view.
    static let guideID = "setupGuide"

    /// Scrolls after the pending state change has been laid out.
    static func scroll(_ proxy: ScrollViewProxy, to id: some Hashable & Sendable) {
        DispatchQueue.main.async {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    /// General > Setup guide. While the first-run guide is still open this only
    /// scrolls back to it, so progress made so far is kept.
    static func showGuide(_ session: Binding<SetupGuideSession>, model: AppModel, scroll proxy: ScrollViewProxy) {
        if model.config.hasCompletedSetup, !session.wrappedValue.isReopened {
            var next = SetupGuideSession()
            next.isReopened = true
            withAnimation(DesignTokens.Motion.resolved(
                DesignTokens.Motion.expandCollapse,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )) {
                session.wrappedValue = next
            }
        }
        scroll(proxy, to: guideID)
    }

    static func announce(_ message: String) {
        let element: Any = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}
