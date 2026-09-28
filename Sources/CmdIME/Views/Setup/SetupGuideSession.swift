import AppKit
import Combine
import KeyboardSwitcherCore
import SwiftUI

typealias SetupTriggerEvents = PassthroughSubject<SetupTriggeredSwitch, Never>

/// Session-only state of the setup guide. Completion and the seen release version
/// are stored separately in `SwitcherConfig`.
struct SetupGuideSession: Equatable {
    /// The user pressed "Looks right" in the review step.
    var hasConfirmedSlots = false
    /// A returning user reopened the guide from General > Show Setup Guide.
    var isReopened = false
    /// Successful trigger/source evidence for the current configuration, never persisted.
    var triggerEvidence = SetupTriggerEvidence()
    /// macOS reports some grants only to a fresh process. Once step 1 opened a settings
    /// pane and a permission still reads as missing, the restart hint appears.
    var didOpenPermissionSettings = false
    /// Scheduling a relaunch from step 1 failed; offer Quit instead.
    var relaunchFailed = false
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
            listenerRunning: isListening,
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
        config = config.completingSetup(whatsNewVersion: Self.currentVersion)
        save()
    }
}

@MainActor
enum SetupGuideNavigation {
    /// General > Show Setup Guide. A returning user gets a fresh walk through the steps;
    /// while the first-run guide is still open the session is kept, so progress made so
    /// far survives. The caller selects the Setup page.
    static func showGuide(_ session: Binding<SetupGuideSession>, model: AppModel) {
        guard model.config.hasCompletedSetup, !session.wrappedValue.isReopened else { return }
        var next = SetupGuideSession()
        next.isReopened = true
        withAnimation(DesignTokens.Motion.resolved(
            DesignTokens.Motion.expandCollapse,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )) {
            session.wrappedValue = next
        }
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
